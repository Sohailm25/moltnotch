// ABOUTME: NSPanel subclass for the notch popup, positioned above the menu bar.
// ABOUTME: Borderless, non-activating, key-capable panel that dismisses on focus loss.

import AppKit

final class NotchPanel: NSPanel, NSWindowDelegate {
    override var canBecomeKey: Bool { true }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing bufferingType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.delegate = self
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    func windowDidResignKey(_ notification: Notification) {
        guard NotchPanelManager.isVisible else { return }
        NotchPanelManager.hide()
    }
}
