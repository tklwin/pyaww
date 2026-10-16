import AppKit
import ApplicationServices
import AVFoundation
import Observation

/// Microphone + Accessibility status with System Settings deep links (FR-9).
@MainActor
@Observable
final class PermissionsManager {
    private(set) var microphoneStatus: AVAuthorizationStatus
    private(set) var accessibilityTrusted: Bool

    init() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityTrusted = AXIsProcessTrusted()
    }

    var isMicrophoneGranted: Bool { microphoneStatus == .authorized }

    /// Re-reads both permissions (e.g. after returning from System Settings).
    func refresh() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityTrusted = AXIsProcessTrusted()
    }

    /// Shows the standard macOS microphone prompt (only when not yet decided).
    func requestMicrophoneAccessIfNeeded() async {
        guard microphoneStatus == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    /// Shows the Accessibility prompt ("…would like to control this computer") —
    /// needed for the global hotkey and the synthetic paste.
    func promptAccessibilityIfNeeded() {
        guard !accessibilityTrusted else { return }
        // "AXTrustedCheckOptionPrompt" is the documented value of the
        // `kAXTrustedCheckOptionPrompt` global, which is not safe to read
        // under Swift 6 strict concurrency.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
