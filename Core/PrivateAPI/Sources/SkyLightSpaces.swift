import CoreGraphics
import Foundation

/// Reads and manipulates Mission Control spaces through SkyLight.
public struct SkyLightSpaces: SpacesReading, WindowSpaceMoving {
    private let bridge: SkyLightBridge

    /// Returns `nil` when SkyLight is unavailable, so callers degrade instead of crashing.
    public init?() {
        guard let bridge = SkyLightBridge.shared else { return nil }
        self.bridge = bridge
    }

    public func displays() -> [DisplaySpaces] {
        bridge.managedDisplaySpaces().compactMap { display in
            guard let displayUUID = display["Display Identifier"] as? String else { return nil }

            let spaces = (display["Spaces"] as? [[String: Any]] ?? [])
                .enumerated()
                .compactMap { index, space -> SpaceInfo? in
                    guard let id = space["id64"] as? SpaceID else { return nil }

                    return SpaceInfo(
                        id: id,
                        uuid: space["uuid"] as? String,
                        kind: SpaceKind(rawType: space["type"] as? Int ?? -1),
                        index: index + 1
                    )
                }

            return DisplaySpaces(
                displayUUID: displayUUID,
                currentSpaceID: bridge.currentSpaceID(displayUUID: displayUUID),
                spaces: spaces
            )
        }
    }

    public func windowIDs(onSpace spaceID: SpaceID) -> [CGWindowID] {
        bridge.windowIDs(onSpace: spaceID)
    }

    public func spaceIDs(ofWindow windowID: CGWindowID) -> [SpaceID] {
        bridge.spaceIDs(ofWindow: windowID)
    }

    public func move(windowIDs: [CGWindowID], toSpace spaceID: SpaceID) async throws {
        guard !windowIDs.isEmpty else { return }

        try bridge.requestBridgedMove(windowIDs: windowIDs, toSpace: spaceID)

        let deadline = ContinuousClock.now + Self.moveConfirmationTimeout

        while ContinuousClock.now < deadline {
            let unmoved = windowIDs.filter { !spaceIDs(ofWindow: $0).contains(spaceID) }
            if unmoved.isEmpty { return }

            try await Task.sleep(for: Self.moveConfirmationPollInterval)
        }

        let unmoved = windowIDs.filter { !spaceIDs(ofWindow: $0).contains(spaceID) }
        guard unmoved.isEmpty else {
            throw PrivateAPIError.moveNotConfirmed(windowIDs: unmoved, spaceID: spaceID)
        }
    }

    private static let moveConfirmationTimeout = Duration.seconds(2)
    private static let moveConfirmationPollInterval = Duration.milliseconds(50)
}
