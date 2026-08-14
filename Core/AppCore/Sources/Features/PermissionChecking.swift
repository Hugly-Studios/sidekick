/// Result of asking the system whether a permission is available.
public enum PermissionStatus: String, Sendable, Codable, CaseIterable {
    case granted
    case denied
    case notDetermined
}

/// How the kernel checks and requests system permissions.
///
/// `AppCore` owns the contract; `PermissionsKit` supplies the live implementation.
public protocol PermissionChecking: Sendable {
    func status(of kind: PermissionKind) -> PermissionStatus
    func request(_ kind: PermissionKind) async -> PermissionStatus
    func openSettings(for kind: PermissionKind)
}

/// Grants every permission. Used in unit tests that are not about TCC.
public struct UncheckedPermissions: PermissionChecking {
    public init() {}

    public func status(of kind: PermissionKind) -> PermissionStatus { .granted }

    public func request(_ kind: PermissionKind) async -> PermissionStatus { .granted }

    public func openSettings(for kind: PermissionKind) {}
}
