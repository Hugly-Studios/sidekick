import CoreGraphics
import Foundation

public typealias SpaceID = UInt64

public enum SpaceKind: Sendable, Equatable {
    /// An ordinary desktop.
    case user
    /// A space created by a full-screen or tiled app.
    case fullscreen
    case other(Int)

    init(rawType: Int) {
        switch rawType {
        case 0: self = .user
        case 4: self = .fullscreen
        default: self = .other(rawType)
        }
    }
}

public struct SpaceInfo: Sendable, Identifiable, Equatable {
    public let id: SpaceID
    public let uuid: String?
    public let kind: SpaceKind
    /// 1-based position on its display, i.e. the order shown in Mission Control.
    public let index: Int

    public init(id: SpaceID, uuid: String?, kind: SpaceKind, index: Int) {
        self.id = id
        self.uuid = uuid
        self.kind = kind
        self.index = index
    }
}

public struct DisplaySpaces: Sendable, Identifiable, Equatable {
    public let displayUUID: String
    public let currentSpaceID: SpaceID
    public let spaces: [SpaceInfo]

    public var id: String { displayUUID }

    public init(displayUUID: String, currentSpaceID: SpaceID, spaces: [SpaceInfo]) {
        self.displayUUID = displayUUID
        self.currentSpaceID = currentSpaceID
        self.spaces = spaces
    }
}

public protocol SpacesReading: Sendable {
    /// Displays with their spaces in on-screen order.
    func displays() -> [DisplaySpaces]
    func windowIDs(onSpace spaceID: SpaceID) -> [CGWindowID]
    func spaceIDs(ofWindow windowID: CGWindowID) -> [SpaceID]
}

public protocol WindowSpaceMoving: Sendable {
    /// Moves windows to a space and waits until the WindowServer confirms it.
    func move(windowIDs: [CGWindowID], toSpace spaceID: SpaceID) async throws
}

public enum PrivateAPIError: Error, LocalizedError, Equatable {
    case skyLightUnavailable
    case symbolUnavailable(String)
    case moveNotConfirmed(windowIDs: [CGWindowID], spaceID: SpaceID)

    public var errorDescription: String? {
        switch self {
        case .skyLightUnavailable:
            "Системный компонент SkyLight недоступен на этой версии macOS"
        case .symbolUnavailable(let name):
            "Точка входа \(name) отсутствует в этой версии macOS"
        case .moveNotConfirmed(let windowIDs, let spaceID):
            "Не удалось перенести окна \(windowIDs) на рабочий стол \(spaceID)"
        }
    }
}
