import AppKit
import Observation
import SwiftUI

/// Owns the menu bar item and its popover (owner decision 2026-10-18).
///
/// The app hosts its own `NSPopover` on a plain `NSStatusItem` instead of
/// SwiftUI's `MenuBarExtra` — the pattern learned from vorssaint's status
/// item: `MenuBarExtra` pinned its plain square panel to the screen corner,
/// while `NSPopover` anchors centred under the icon and draws the
/// round-cornered container with the arrow notch itself.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    /// Timestamp of the last popover close: a click on the status item that
    /// just dismissed the transient popover must not reopen it immediately.
    private var lastClose = Date.distantPast

    init(model: AppModel) {
        self.model = model
        super.init()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "PyawwMainItem"
        if let button = item.button {
            button.image = MenuBarIcon.image(for: model.state)
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Pyaww — hold the push-to-talk key and speak"
        }
        statusItem = item

        let hosting = NSHostingController(rootView: MenuPanelView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        observeState()
    }

    /// Both mouse buttons toggle the panel (owner decision 2026-10-18:
    /// no right-click menu — the teacher-style Quit button lives in the
    /// panel footer instead).
    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        // A transient popover closes on the mouse-down of the very click
        // that lands on the status item; by mouse-up it is already closed
        // and this action would reopen it. Ignore that one click.
        guard Date().timeIntervalSince(lastClose) > 0.25 else { return }
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // An accessory app's popover does not become key on its own, and
        // controls only take clicks in a key window.
        DispatchQueue.main.async { [popover] in
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastClose = Date()
    }

    // MARK: - Icon state

    /// Re-renders the menu bar icon whenever the state it reads changes
    /// (`withObservationTracking` only reports one change per registration).
    private func observeState() {
        withObservationTracking {
            statusItem?.button?.image = MenuBarIcon.image(for: model.state)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeState()
            }
        }
    }
}
