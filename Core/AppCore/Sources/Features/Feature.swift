import SwiftUI

/// Stable identifier of a feature module, e.g. `"awake"`.
public struct FeatureID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

/// Everything the app shell needs to know about a feature without instantiating it.
public struct FeatureDescriptor: Sendable, Identifiable {
    public let id: FeatureID
    public let title: String
    public let summary: String
    public let symbolName: String
    public let requiredPermissions: [PermissionKind]
    public let isEnabledByDefault: Bool

    public init(
        id: FeatureID,
        title: String,
        summary: String,
        symbolName: String,
        requiredPermissions: [PermissionKind] = [],
        isEnabledByDefault: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbolName = symbolName
        self.requiredPermissions = requiredPermissions
        self.isEnabledByDefault = isEnabledByDefault
    }
}

/// A feature declares what it can do; the shell decides how to present it.
///
/// A feature never talks to the menu bar, the hotkey engine or the CLI directly —
/// it exposes ``commands`` and views, and the surfaces are built from the registries.
@MainActor
public protocol Feature: AnyObject {
    static var descriptor: FeatureDescriptor { get }

    init(context: FeatureContext)

    /// Called when the feature is enabled. Throw ``FeatureActivationError`` to
    /// surface the reason in the UI instead of failing silently.
    func activate() async throws

    /// Called when the feature is disabled and before the app terminates.
    func deactivate() async

    var commands: [Command] { get }

    /// Live status shown inside the menu bar dropdown.
    func makeMenuView() -> AnyView?

    /// Pane shown in the settings window.
    func makeSettingsView() -> AnyView
}

extension Feature {
    public var commands: [Command] { [] }

    public func makeMenuView() -> AnyView? { nil }
}

public enum FeatureActivationError: Error, LocalizedError {
    case missingPermission(PermissionKind)
    case unsupportedSystem(String)

    nonisolated public var errorDescription: String? {
        switch self {
        case .missingPermission(let permission):
            "Требуется разрешение: \(permission.title)"
        case .unsupportedSystem(let reason):
            reason
        }
    }
}
