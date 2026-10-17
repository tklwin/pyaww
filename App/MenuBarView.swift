import AppKit
import SwiftUI
import PyawwCore

/// Menu bar menu content (FR-1, FR-8, FR-9).
struct MenuBarView: View {
    let model: AppModel

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
                openSettingsWindow()
            }
            Button("Quit Pyaww") {
                NSApp.terminate(nil)
            }
        }
        .onAppear {
            model.refreshPermissions()
        }
    }

    /// Opens the SwiftUI Settings window and brings it to the front.
    ///
    /// Pyaww is an accessory app (`LSUIElement`), so clicking a menu bar
    /// item does not activate it: SwiftUI's `SettingsLink` created the
    /// window *behind* the frontmost app — findable only via Mission
    /// Control. Activate first, open the window, then order it front as a
    /// belt (activation raises the key window, which need not be this one).
    private func openSettingsWindow() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        Task { @MainActor in
            let settingsWindow = NSApp.windows.first { window in
                window.identifier?.rawValue.contains("Settings") == true
                    || window.title.contains("Settings")
            }
            settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }
}

/// Menu bar icon per state: idle, recording, transcribing, error (FR-8).
struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        Image(systemName: state.menuBarSymbol)
    }
}
