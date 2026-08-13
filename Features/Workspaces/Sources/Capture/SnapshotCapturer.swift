import Automation
import CoreGraphics
import Foundation
import PrivateAPI

/// Records the current layout: desktops in order, and the windows on each.
///
/// Walks the desktops on purpose. Accessibility only exposes windows of the
/// visible desktop, so the only way to learn where windows are and how big they
/// are is to go to each desktop in turn and look. The original desktop is
/// restored afterwards.
@MainActor
public struct SnapshotCapturer {
    private let spaces: any SpacesReading
    private let navigator: any SpaceNavigating
    private let inspector: WindowInspector

    public init(
        spaces: any SpacesReading,
        navigator: any SpaceNavigating,
        inspector: WindowInspector = WindowInspector()
    ) {
        self.spaces = spaces
        self.navigator = navigator
        self.inspector = inspector
    }

    public func capture(name: String) async throws -> WorkspaceSnapshot {
        var displays: [DisplaySnapshot] = []

        for display in spaces.displays() {
            displays.append(try await capture(display: display))
        }

        return WorkspaceSnapshot(name: name, displays: displays)
    }

    private func capture(display: DisplaySpaces) async throws -> DisplaySnapshot {
        let originalSpaceID = display.currentSpaceID
        var snapshots: [SpaceSnapshot] = []

        for space in display.spaces {
            try await navigator.activate(spaceID: space.id, displayUUID: display.displayUUID)

            snapshots.append(
                SpaceSnapshot(
                    index: space.index,
                    uuid: space.uuid,
                    kind: Self.kind(of: space.kind),
                    isActive: space.id == originalSpaceID,
                    windows: try windows(onSpace: space.id)
                )
            )
        }

        try await navigator.activate(spaceID: originalSpaceID, displayUUID: display.displayUUID)

        return DisplaySnapshot(uuid: display.displayUUID, spaces: snapshots)
    }

    /// Keeps the front-to-back order the WindowServer reports, which is what
    /// matching falls back to when titles are ambiguous.
    private func windows(onSpace spaceID: SpaceID) throws -> [WindowSnapshot] {
        let identifiers = spaces.windowIDs(onSpace: spaceID)
        let visible = try Dictionary(
            inspector.windows(withIDs: Set(identifiers)).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return identifiers
            .compactMap { visible[$0] }
            .map { window in
                WindowSnapshot(
                    bundleID: window.bundleID,
                    appName: window.appName,
                    title: window.title,
                    frame: FrameSnapshot(window.frame),
                    isMinimized: window.isMinimized,
                    isFullscreen: window.isFullscreen
                )
            }
    }

    private static func kind(of kind: SpaceKind) -> SpaceSnapshot.Kind {
        switch kind {
        case .user: .user
        case .fullscreen: .fullscreen
        case .other: .other
        }
    }
}
