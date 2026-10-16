import AppKit
import Carbon.HIToolbox
import PyawwCore

/// Paste-at-cursor via the clipboard + synthetic ⌘V, restoring the previous
/// clipboard afterwards (SPEC §6.5). When pasting is impossible (no
/// Accessibility permission, secure input field), the text is left on the
/// clipboard so it is never lost.
@MainActor
final class TextInserter: TextInserting {
    /// Wait before restoring, so slow target apps have read the new value.
    private static let restoreDelay = Duration.milliseconds(400)
    private static let pasteKeyCode: CGKeyCode = 9 // kVK_ANSI_V

    func insert(_ text: String, restoreClipboard: Bool) async -> InsertionOutcome {
        let pasteboard = NSPasteboard.general
        let secureInput = IsSecureEventInputEnabled()
        let accessibilityTrusted = AXIsProcessTrusted()

        guard accessibilityTrusted, !secureInput else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            let reason = secureInput
                ? "secure input is on (password field) — text copied to the clipboard instead"
                : "Accessibility permission is off — text copied to the clipboard instead"
            return .copiedToClipboardOnly(reason: reason)
        }

        let savedItems = Self.snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let writtenChangeCount = pasteboard.changeCount
        postCommandV()

        guard restoreClipboard else { return .pasted }
        try? await Task.sleep(for: Self.restoreDelay)
        if pasteboard.changeCount == writtenChangeCount, !savedItems.isEmpty {
            pasteboard.clearContents()
            pasteboard.writeObjects(savedItems)
        }
        return .pasted
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.pasteKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.pasteKeyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Copies every pasteboard item with all of its types (SPEC §6.5:
    /// preserve all pasteboard types, not just plain text).
    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }
}
