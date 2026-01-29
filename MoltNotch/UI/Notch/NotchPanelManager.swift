// ABOUTME: Static manager owning the NotchPanel, handling show/hide lifecycle.
// ABOUTME: Detects notch on mouse-cursor screen, positions panel, and manages emergence animation.

import SwiftUI

enum NotchPanelManager {
    enum PanelState {
        case hidden
        case visible
        case closing
    }

    private static var panel: NotchPanel?
    private static var state: PanelState = .hidden
    private static var currentHostingView: NSHostingView<AnyView>?
    private static var hideWorkItem: DispatchWorkItem?

    static var isVisible: Bool { state != .hidden }

    static func setup() {
        let newPanel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel = newPanel

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            repositionForCurrentScreen()
        }
    }

    static func toggle<Content: View>(@ViewBuilder content: () -> Content) {
        switch state {
        case .hidden:
            show(content: content)
        case .visible:
            hide()
        case .closing:
            cancelPendingHide()
            state = .visible
            NotificationCenter.default.post(name: .notchPanelWillShow, object: nil)
            if let panel = panel {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    static func show<Content: View>(@ViewBuilder content: () -> Content) {
        guard let panel = panel else { return }

        cancelPendingHide()

        let screen = NotchDetector.screenWithMouseCursor() ?? NSScreen.main ?? NSScreen.screens.first!
        let hasNotch = screen.hasNotch
        let notchSize = screen.notchSize

        let canvasWidth = screen.frame.width / 2
        let canvasHeight = screen.frame.height / 2
        let panelX = screen.frame.midX - canvasWidth / 2
        let panelY = screen.frame.maxY - canvasHeight

        let panelFrame = NSRect(
            x: panelX,
            y: panelY,
            width: canvasWidth,
            height: canvasHeight
        )
        panel.setFrame(panelFrame, display: false)

        let wrappedContent = NotchPopupView(
            hasNotch: hasNotch,
            notchWidth: notchSize.width,
            notchHeight: notchSize.height
        ) {
            content()
        }

        let hostingView = NSHostingView(rootView: AnyView(wrappedContent))
        hostingView.safeAreaRegions = []
        hostingView.frame = NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        panel.contentView = hostingView
        currentHostingView = hostingView

        panel.layoutIfNeeded()
        panel.orderFrontRegardless()
        state = .visible

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    static func hide() {
        guard state == .visible else { return }
        state = .closing

        NotificationCenter.default.post(name: .notchPanelWillHide, object: nil)

        let duration = Double(Constants.notchAnimationDurationInMilliseconds) / 1000.0
        let workItem = DispatchWorkItem {
            panel?.orderOut(nil)
            currentHostingView = nil
            state = .hidden
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    static func repositionForCurrentScreen() {
        guard state != .hidden, let panel = panel else { return }
        let screen = NotchDetector.screenWithMouseCursor() ?? NSScreen.main ?? NSScreen.screens.first!

        let canvasWidth = screen.frame.width / 2
        let canvasHeight = screen.frame.height / 2
        let panelX = screen.frame.midX - canvasWidth / 2
        let panelY = screen.frame.maxY - canvasHeight

        panel.setFrame(NSRect(x: panelX, y: panelY, width: canvasWidth, height: canvasHeight), display: true)
    }

    private static func cancelPendingHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }
}

extension Notification.Name {
    static let notchPanelWillHide = Notification.Name("notchPanelWillHide")
    static let notchPanelWillShow = Notification.Name("notchPanelWillShow")
}
