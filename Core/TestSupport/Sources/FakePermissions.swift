import AppCore
import Foundation

public final class FakePermissions: PermissionChecking, @unchecked Sendable {
    public var statuses: [PermissionKind: PermissionStatus]
    public private(set) var requested: [PermissionKind] = []
    public private(set) var opened: [PermissionKind] = []

    public init(_ statuses: [PermissionKind: PermissionStatus] = [:]) {
        self.statuses = statuses
    }

    public func status(of kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .denied
    }

    public func request(_ kind: PermissionKind) async -> PermissionStatus {
        requested.append(kind)
        return status(of: kind)
    }

    public func openSettings(for kind: PermissionKind) {
        opened.append(kind)
    }

    public func grant(_ kind: PermissionKind) {
        statuses[kind] = .granted
    }
}
