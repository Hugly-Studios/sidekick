import ApplicationServices

/// Accessibility permission, without which no window can be read or moved.
///
/// Read-only on purpose: requesting the grant and deep-linking to System
/// Settings belong to `PermissionsKit`, which the registry drives.
public enum AccessibilityAuthorization {
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }
}
