import AppKit
import SwiftUI
import PyawwCore

/// Menu bar menu content (FR-1, FR-8, FR-9).
struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            Text(model.state.statusText)
            if let notice = model.state.notice {
                Text(notice)
            }
            if !model.permissions.isMicrophoneGranted {
                Divider()
                Button("Grant Microphone Access…") {
                    Task { await model.permissions.requestMicrophoneAccessIfNeeded() }
                }
                Button("Open Microphone Settings…") {
                    model.permissions.openMicrophoneSettings()
                }
            }
            if !model.permissions.accessibilityTrusted {
                Divider()
                Button("Grant Accessibility Access…") {
                    model.permissions.promptAccessibilityIfNeeded()
                }
                Button("Open Accessibility Settings…") {
                    model.permissions.openAccessibilitySettings()
                }
            }
            if !model.permissions.isMicrophoneGranted || !model.permissions.accessibilityTrusted {
                Button("Refresh Permission Status") {
                    model.refreshPermissions()
                }
            }
            Divider()
            Button("Settings…") {
                showSettings()
            }
            Button("Quit Pyaww") {
                NSApp.terminate(nil)
            }
        }
        .onAppear {
            model.refreshPermissions()
        }
    }

    /// Opens the Settings window in front of other apps (FR-10).
    ///
    /// Activate first — menu bar clicks do not activate an accessory app —
    /// then open the window via the public `openSettings` action and order
    /// it front (details and probe evidence in `SettingsWindow`).
    private func showSettings() {
        SettingsWindow.activateApp()
        openSettings()
        SettingsWindow.raiseWhenReady()
    }
}

/// Menu bar icon per state: idle, recording, transcribing, error (FR-8).
struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        Image(systemName: state.menuBarSymbol)
    }
}
