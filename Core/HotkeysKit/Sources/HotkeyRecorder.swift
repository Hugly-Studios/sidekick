import KeyboardShortcuts
import SwiftUI

/// Shortcut picker for settings panes.
///
/// Storage and system-conflict warnings are handled by the library.
public struct HotkeyRecorder: View {
    private let title: String
    private let name: KeyboardShortcuts.Name

    public init(_ title: String, name: KeyboardShortcuts.Name) {
        self.title = title
        self.name = name
    }

    public var body: some View {
        KeyboardShortcuts.Recorder(title, name: name)
    }
}
