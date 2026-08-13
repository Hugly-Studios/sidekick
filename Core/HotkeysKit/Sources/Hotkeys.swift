import KeyboardShortcuts

/// Global shortcuts owned by the app shell.
///
/// Feature shortcuts will be registered from their commands; these are the ones
/// that must work even when no feature is enabled.
public enum Hotkeys {
    /// Opens the Sidekick window. Deliberately a four-modifier chord: it has to
    /// be reachable when the menu bar icon is not, without colliding with apps.
    public static let openPanel = KeyboardShortcuts.Name(
        "openPanel",
        default: .init(.s, modifiers: [.control, .option, .command])
    )
}
