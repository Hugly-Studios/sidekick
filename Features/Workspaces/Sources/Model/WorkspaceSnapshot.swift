import CoreGraphics
import Foundation

/// Saved layout: every desktop, in order, with the windows that were on it.
public struct WorkspaceSnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var displays: [DisplaySnapshot]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        displays: [DisplaySnapshot]
    ) {
        self.id = id
        self.name = name
        // The stored format keeps whole seconds, so the value is normalized here
        // and a saved snapshot stays equal to the one in memory.
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded())
        self.displays = displays
    }

    public var windowCount: Int {
        displays.flatMap(\.spaces).map(\.windows.count).reduce(0, +)
    }

    public var spaceCount: Int {
        displays.map(\.spaces.count).reduce(0, +)
    }

    /// Space identities in on-screen order, used to detect reordering.
    public var spaceOrder: [String] {
        displays.flatMap(\.spaces).compactMap(\.uuid)
    }
}

public struct DisplaySnapshot: Codable, Sendable, Equatable {
    public var uuid: String
    public var spaces: [SpaceSnapshot]

    public init(uuid: String, spaces: [SpaceSnapshot]) {
        self.uuid = uuid
        self.spaces = spaces
    }
}

public struct SpaceSnapshot: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case user
        case fullscreen
        case other
    }

    /// 1-based position on its display, the same order Mission Control shows.
    public var index: Int
    public var uuid: String?
    public var kind: Kind
    public var isActive: Bool
    public var windows: [WindowSnapshot]

    public init(
        index: Int,
        uuid: String?,
        kind: Kind,
        isActive: Bool,
        windows: [WindowSnapshot]
    ) {
        self.index = index
        self.uuid = uuid
        self.kind = kind
        self.isActive = isActive
        self.windows = windows
    }
}

public struct WindowSnapshot: Codable, Sendable, Equatable {
    public var bundleID: String
    public var appName: String
    public var title: String
    public var frame: FrameSnapshot
    public var isMinimized: Bool
    public var isFullscreen: Bool

    public init(
        bundleID: String,
        appName: String,
        title: String,
        frame: FrameSnapshot,
        isMinimized: Bool,
        isFullscreen: Bool
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
    }
}

/// Stored explicitly instead of relying on `CGRect`'s encoding, so the JSON stays
/// readable and stable across OS and Swift versions.
public struct FrameSnapshot: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
