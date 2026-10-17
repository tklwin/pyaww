import AppKit

/// Fronting helpers for the SwiftUI Settings window (FR-10).
///
/// Pyaww is an accessory app (`LSUIElement`) and menu bar clicks do not
/// activate it, so the Settings window would otherwise open behind the
/// frontmost app. Findings from probing macOS 27.0.1 with a scratch
/// `LSUIElement` app (2026-10-17):
///
/// - the private `showSettingsWindow:` selector is *answered* but no longer
///   creates the window;
/// - the public `openSettings` action creates the window
///   (`com_apple_SwiftUI_Settings_window`) without activating the app;
/// - the cooperative activation APIs (`NSApp.activate()`,
///   `NSRunningApplication.activate(options:)`) are no-ops for an accessory
///   app;
/// - `activate(ignoringOtherApps:)` (deprecated on macOS 14, but functional)
///   activates it, after which the window becomes key and comes to the
///   front.
@MainActor
enum SettingsWindow {
    /// The identifier SwiftUI gives its Settings scene window.
    private static let identifier = "com_apple_SwiftUI_Settings_window"

    /// Activates Pyaww so its windows can come to the front.
    static func activateApp() {
        NSApp.activate(ignoringOtherApps: true) // the only call that works; see above
    }

    /// Orders the Settings window to the front once it exists.
    ///
    /// `openSettings()` may create the window after a runloop pass, so retry
    /// briefly; this also covers the case where the window already existed
    /// behind other apps.
    static func raiseWhenReady() {
        Task {
            for _ in 0..<6 {
                if let window = NSApp.windows.first(where: isSettings) {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private static func isSettings(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == identifier
            || window.title.contains("Settings")
    }
}
