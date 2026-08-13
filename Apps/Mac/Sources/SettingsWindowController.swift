import AppKit
import SwiftUI

/// Owns the settings window instead of relying on SwiftUI's `Settings` scene.
///
/// The scene can only be opened by the user through `SettingsLink`, and the menu
/// bar icon is not always reachable — on notched Macs a full menu bar pushes new
/// status items behind the notch. Owning the window lets the app open it on first
/// launch and later from a global hotkey.
@MainActor
final class SettingsWindowController {
    private let environment: AppEnvironment
    private var window: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Sidekick"
        window.contentView = NSHostingView(rootView: SettingsRootView(environment: environment))
        window.isReleasedWhenClosed = false
        window.center()

        return window
    }
}
