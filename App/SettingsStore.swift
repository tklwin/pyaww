import Foundation
import Observation
import ServiceManagement

/// User settings, persisted in `UserDefaults` (FR-10).
@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let pushToTalk = "pushToTalkKey"
        static let minimumDuration = "minimumDuration"
        static let maximumDuration = "maximumDuration"
        static let restoreClipboard = "restoreClipboard"
        static let soundCue = "soundCue"
    }

    /// Options offered for the minimum recording length (FR-5, default 0.3 s).
    static let minimumDurationChoices: [Double] = [0.3, 0.5, 1.0, 2.0]
    /// Options offered for the maximum recording length (FR-6, capped by I-9 = 30 s).
    static let maximumDurationChoices: [Double] = [5, 10, 15, 30]

    private let defaults: UserDefaults

    var pushToTalkKey: PushToTalkKey {
        didSet { defaults.set(pushToTalkKey.rawValue, forKey: Key.pushToTalk) }
    }
    var minimumDuration: Double {
        didSet { defaults.set(minimumDuration, forKey: Key.minimumDuration) }
    }
    var maximumDuration: Double {
        didSet { defaults.set(maximumDuration, forKey: Key.maximumDuration) }
    }
    var restoreClipboard: Bool {
        didSet { defaults.set(restoreClipboard, forKey: Key.restoreClipboard) }
    }
    var soundCue: Bool {
        didSet { defaults.set(soundCue, forKey: Key.soundCue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.pushToTalkKey = defaults.string(forKey: Key.pushToTalk)
            .flatMap(PushToTalkKey.init(rawValue:)) ?? .rightOption
        self.minimumDuration = defaults.object(forKey: Key.minimumDuration) as? Double ?? 0.3
        self.maximumDuration = defaults.object(forKey: Key.maximumDuration) as? Double ?? 30
        self.restoreClipboard = defaults.object(forKey: Key.restoreClipboard) as? Bool ?? true
        self.soundCue = defaults.object(forKey: Key.soundCue) as? Bool ?? false
    }

    /// Mirrors `SMAppService.mainApp`; registration only works when running
    /// from a bundle (unbundled development runs silently stay off).
    var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled) {
        didSet { applyLaunchAtLogin() }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Show reality when registration fails.
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
