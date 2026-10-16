import AppKit
import Observation

/// Supported push-to-talk keys (FR-2/FR-10). Both are pure modifiers, so the
/// key-down/key-up pair comes from `flagsChanged` events.
enum PushToTalkKey: String, CaseIterable, Identifiable, Sendable {
    case rightOption
    case rightCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightOption: return "Right Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        }
    }

    /// Virtual key code reported by `flagsChanged` for this modifier.
    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61  // kVK_RightOption
        case .rightCommand: return 54 // kVK_RightCommand
        }
    }

    /// The modifier flag this key toggles.
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: return .option
        case .rightCommand: return .command
        }
    }
}

/// Global push-to-talk + Esc handling via `NSEvent` monitors (SPEC §6.5).
///
/// Choice: global + local `flagsChanged`/`keyDown` monitors. They are the
/// simplest API that reliably delivers both modifier-down and modifier-up
/// (a `CGEventTap` can do the same but needs a run-loop source and more
/// setup); both approaches require the same Accessibility permission, which
/// the app guides the user to grant.
@MainActor
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var key: PushToTalkKey = .rightOption
    private var isKeyDown = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func setKey(_ key: PushToTalkKey) {
        self.key = key
        isKeyDown = false
    }

    func startMonitoring() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let handler: (NSEvent) -> Void = { [weak self] event in
            // NSEvent monitor handlers are delivered on the main thread.
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown], handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown]) { event in
                handler(event)
                return event
            }
    }

    func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isKeyDown = false
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            guard event.keyCode == key.keyCode else { return }
            let down = event.modifierFlags.contains(key.flag)
            if down, !isKeyDown {
                isKeyDown = true
                onPress?()
            } else if !down, isKeyDown {
                isKeyDown = false
                onRelease?()
            }
        case .keyDown:
            if event.keyCode == 53 { // kVK_Escape
                onCancel?()
            }
        default:
            break
        }
    }
}
