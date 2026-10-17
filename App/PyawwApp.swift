import AppKit
import Foundation
import Observation
import SwiftUI
import os
import PyawwCore

/// Pyaww — menu bar Myanmar dictation (SPEC §4). No Dock icon (LSUIElement).
///
/// Note: this machine has Command Line Tools only, whose toolchain does not
/// ship `SwiftUIMacros`; the app therefore avoids SwiftUI property-wrapper
/// macros (`@State`, `@Environment`, …) and uses Observation (`@Observable`,
/// `@Bindable`) instead — SwiftUI tracks observable reads in `body` directly.
@main
struct PyawwApp: App {
    private let model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            MenuBarLabel(state: model.state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}

/// Composition root: builds the object graph, wires the hotkey callbacks,
/// starts the monitor, and loads the model off the main thread (SPEC §6.1).
@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let permissions: PermissionsManager
    let recorder: AudioRecorder
    let hotkey: HotkeyManager
    let inserter: TextInserter
    let state: AppState

    private let logger = Logger(subsystem: "com.tklwin.pyaww", category: "app")
    /// Reference point for the cold-start measurement (Phase 3 target).
    private let launchTime = ContinuousClock.now
    private var modelLoadTask: Task<Void, Never>?

    init() {
        let settings = SettingsStore()
        let permissions = PermissionsManager()
        let recorder = AudioRecorder()
        let inserter = TextInserter()
        let hotkey = HotkeyManager()
        let state = AppState(settings: settings, recorder: recorder, inserter: inserter)
        self.settings = settings
        self.permissions = permissions
        self.recorder = recorder
        self.inserter = inserter
        self.hotkey = hotkey
        self.state = state

        // No Dock icon even when run unbundled during development.
        NSApplication.shared.setActivationPolicy(.accessory)

        hotkey.setKey(settings.pushToTalkKey)
        hotkey.onPress = { [weak state] in state?.hotkeyPressed() }
        hotkey.onRelease = { [weak state] in state?.hotkeyReleased() }
        hotkey.onCancel = { [weak state] in state?.cancel() }
        hotkey.startMonitoring()

        // First-run permission guidance (FR-9): microphone prompt, then the
        // Accessibility prompt (both are no-ops once decided).
        Task { [permissions] in
            await permissions.requestMicrophoneAccessIfNeeded()
            try? await Task.sleep(for: .seconds(1))
            permissions.promptAccessibilityIfNeeded()
        }

        loadModel()
    }

    func applyHotkeySetting() {
        hotkey.setKey(settings.pushToTalkKey)
    }

    /// Re-reads permission status; if Accessibility just became available,
    /// restart the event monitors so the hotkey starts working immediately.
    func refreshPermissions() {
        let wasTrusted = permissions.accessibilityTrusted
        permissions.refresh()
        if permissions.accessibilityTrusted, !wasTrusted {
            hotkey.stopMonitoring()
            hotkey.startMonitoring()
        }
    }

    // MARK: - Model loading

    private func loadModel() {
        let directory = Self.modelDirectory()
        logger.info("loading model from \(directory.path, privacy: .public)")
        modelLoadTask = Task { [state] in
            do {
                let transcriber = try await Task.detached(priority: .userInitiated) {
                    try Transcriber(modelDirectory: directory)
                }.value
                // Warm-up inference (SPEC §6.1): 1 s of digital silence runs
                // the full feature + Core ML path and primes the ANE.
                _ = try? await transcriber.transcribe(samples: [Float](repeating: 0, count: 16_000))
                state.modelDidLoad(transcriber)
                // Notice level so the line is persisted and measurable via
                // `log show` (Phase 3 cold-start evidence).
                let elapsed = self.launchTime.duration(to: .now).components
                let readyMs = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
                self.logger.notice("model ready after \(Int(readyMs)) ms")
            } catch {
                self.logger.error("model load failed: \(String(describing: error), privacy: .public)")
                state.modelLoadFailed(String(describing: error))
            }
        }
    }

    /// Bundled `Contents/Resources/Models` in the .app; the repo's `Models/`
    /// directory for `swift run` development builds.
    private static func modelDirectory() -> URL {
        let candidates: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("Models", isDirectory: true),
            URL(fileURLWithPath: "Models", isDirectory: true),
        ].compactMap { $0 }
        let marker = "BurmeseASR-Encoder-30s.mlpackage"
        for candidate in candidates
        where FileManager.default.fileExists(atPath: candidate.appendingPathComponent(marker).path) {
            return candidate
        }
        return candidates[0]
    }
}
