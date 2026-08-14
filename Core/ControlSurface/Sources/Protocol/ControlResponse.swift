import Foundation

public struct ControlResponse: Codable, Sendable {
    public let id: UUID
    public let ok: Bool
    public let error: String?
    public let payload: Payload?

    public init(id: UUID, ok: Bool, error: String? = nil, payload: Payload? = nil) {
        self.id = id
        self.ok = ok
        self.error = error
        self.payload = payload
    }

    public static func success(id: UUID, payload: Payload) -> ControlResponse {
        ControlResponse(id: id, ok: true, payload: payload)
    }

    public static func failure(id: UUID, error: String) -> ControlResponse {
        ControlResponse(id: id, ok: false, error: error)
    }

    public enum Payload: Codable, Sendable {
        case status(StatusPayload)
        case features([FeatureInfo])
        case feature(FeatureInfo)
        case commands([CommandInfo])
        case run(message: String)
        case setting(key: String, value: String?)
        case logs([LogRecord])
        case doctor(DoctorPayload)
        case quit
    }
}

public struct StatusPayload: Codable, Sendable {
    public var version: String
    public var build: String
    public var path: String
    public var pid: Int32
    public var features: [FeatureInfo]

    public init(
        version: String,
        build: String,
        path: String,
        pid: Int32,
        features: [FeatureInfo]
    ) {
        self.version = version
        self.build = build
        self.path = path
        self.pid = pid
        self.features = features
    }
}

public struct FeatureInfo: Codable, Sendable {
    public var id: String
    public var title: String
    public var enabled: Bool
    public var failure: String?

    public init(id: String, title: String, enabled: Bool, failure: String?) {
        self.id = id
        self.title = title
        self.enabled = enabled
        self.failure = failure
    }
}

public struct CommandInfo: Codable, Sendable {
    public var id: String
    public var title: String
    public var owner: String

    public init(id: String, title: String, owner: String) {
        self.id = id
        self.title = title
        self.owner = owner
    }
}

public struct LogRecord: Codable, Sendable {
    public var date: Date
    public var category: String
    public var level: String
    public var message: String

    public init(date: Date, category: String, level: String, message: String) {
        self.date = date
        self.category = category
        self.level = level
        self.message = message
    }
}

public struct DoctorPayload: Codable, Sendable {
    public var bundleID: String
    public var version: String
    public var build: String
    public var path: String
    public var teamID: String?
    public var signingKind: String
    public var loginItem: String
    public var shortcut: String?
    public var menuBarIcon: String
    public var permissions: [PermissionInfo]
    public var warnings: [String]
    public var running: Bool

    public init(
        bundleID: String,
        version: String,
        build: String,
        path: String,
        teamID: String?,
        signingKind: String,
        loginItem: String,
        shortcut: String?,
        menuBarIcon: String,
        permissions: [PermissionInfo],
        warnings: [String],
        running: Bool
    ) {
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.path = path
        self.teamID = teamID
        self.signingKind = signingKind
        self.loginItem = loginItem
        self.shortcut = shortcut
        self.menuBarIcon = menuBarIcon
        self.permissions = permissions
        self.warnings = warnings
        self.running = running
    }
}

public struct PermissionInfo: Codable, Sendable {
    public var id: String
    public var title: String
    public var status: String
    public var settingsURL: String

    public init(id: String, title: String, status: String, settingsURL: String) {
        self.id = id
        self.title = title
        self.status = status
        self.settingsURL = settingsURL
    }
}
