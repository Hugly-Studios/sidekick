import AppKit

/// Opens the SwiftUI `Settings` scene from AppKit (hotkey, reopen, welcome).
///
/// The scene owns Cmd+, so a second custom window would show a blank pane
/// beside the real one.
@MainActor
final class SettingsWindowController {
    func show() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
