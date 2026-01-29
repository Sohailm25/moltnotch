// ABOUTME: Application delegate handling menu bar setup, hotkey registration, and lifecycle.
// ABOUTME: Initializes NotchPanel, MoltNotchManager, and configures the status bar item.

import AppKit
import SwiftUI
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupNotchPanel()
        setupHotKey()
        checkConfigAndConnect()
        requestScreenCaptureIfNeeded()
    }

    // MARK: - Screen Capture Permission

    private func requestScreenCaptureIfNeeded() {
        if !ScreenCaptureService.hasPermission() {
            ScreenCaptureService.requestPermission()
        }
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MoltNotch")
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            togglePanel()
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit MoltNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Notch Panel

    private func setupNotchPanel() {
        NotchPanelManager.setup()
    }

    private func togglePanel() {
        NotchPanelManager.toggle {
            ChatPopup(manager: MoltNotchManager.shared)
        }
    }

    // MARK: - HotKey

    private func setupHotKey() {
        let config = try? MoltNotchConfig.load()
        let hotkeyConfig = config?.hotkey

        let keyValue = hotkeyConfig?.key ?? "space"
        let modifierNames = hotkeyConfig?.modifiers ?? ["control"]

        guard let key = keyFromString(keyValue) else {
            NSLog("[MoltNotch] Unknown hotkey key: \(keyValue)")
            return
        }

        var modifiers: NSEvent.ModifierFlags = []
        for name in modifierNames {
            switch name.lowercased() {
            case "control", "ctrl": modifiers.insert(.control)
            case "option", "alt": modifiers.insert(.option)
            case "command", "cmd": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            default: NSLog("[MoltNotch] Unknown modifier: \(name)")
            }
        }

        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            self?.togglePanel()
        }
    }

    private func keyFromString(_ value: String) -> Key? {
        switch value.lowercased() {
        case "space": return .space
        case "return", "enter": return .return
        case "tab": return .tab
        case "escape", "esc": return .escape
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        case "i": return .i
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "o": return .o
        case "p": return .p
        case "q": return .q
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "u": return .u
        case "v": return .v
        case "w": return .w
        case "x": return .x
        case "y": return .y
        case "z": return .z
        default: return nil
        }
    }

    // MARK: - Config Check

    private func checkConfigAndConnect() {
        let configPath = MoltNotchConfig.configFilePath()
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            showConfigMissingAlert()
            return
        }
        MoltNotchManager.shared.startConnection()
    }

    private func showConfigMissingAlert() {
        let alert = NSAlert()
        alert.messageText = "MoltNotch Not Configured"
        alert.informativeText = "Run `moltnotch setup` in Terminal to configure MoltNotch."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
