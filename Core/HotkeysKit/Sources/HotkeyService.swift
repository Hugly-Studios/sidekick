import KeyboardShortcuts

/// Binds global shortcuts to actions.
///
/// Wrapping the library keeps the dependency in one module and gives the rest of
/// the app a single place where shortcuts are registered.
@MainActor
public final class HotkeyService {
    public init() {}

    public func bind(_ name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: name, action: action)
    }

    public func unbind(_ name: KeyboardShortcuts.Name) {
        KeyboardShortcuts.disable(name)
    }

    /// Human readable shortcut, or `nil` when the user cleared it.
    public static func shortcutDescription(for name: KeyboardShortcuts.Name) -> String? {
        KeyboardShortcuts.getShortcut(for: name)?.description
    }
}
