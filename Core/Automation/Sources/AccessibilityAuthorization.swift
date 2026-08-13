import AppKit
import ApplicationServices

/// Accessibility permission, without which no window can be read or moved.
public enum AccessibilityAuthorization {
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt once per app version; afterwards macOS stays silent
    /// and the user has to go to System Settings.
    public static func prompt() {
        // The kAXTrustedCheckOptionPrompt constant is a mutable global and cannot be
        // read under Swift 6 concurrency checking; its value is this key.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func openSystemSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else { return }

        NSWorkspace.shared.open(url)
    }
}
