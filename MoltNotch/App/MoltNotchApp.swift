// ABOUTME: Entry point for the MoltNotch macOS menu bar application.
// ABOUTME: Uses NSApplicationDelegateAdaptor for AppKit integration with SwiftUI lifecycle.

import SwiftUI

@main
struct MoltNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
