import Automation
import CoreGraphics
import Foundation
import PrivateAPI

/// Records the current layout: desktops in order, and the windows on each.
@MainActor
public struct SnapshotCapturer {
    private let spaces: any SpacesReading
    private let inspector: WindowInspector

    public init(spaces: any SpacesReading, inspector: WindowInspector = WindowInspector()) {
        self.spaces = spaces
        self.inspector = inspector
    }

    public func capture(name: String) throws -> WorkspaceSnapshot {
        let windowsByID = try Dictionary(
            inspector.windows().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let displays = spaces.displays().map { display in
            DisplaySnapshot(
                uuid: display.displayUUID,
                spaces: display.spaces.map { space in
                    SpaceSnapshot(
                        index: space.index,
                        uuid: space.uuid,
                        kind: Self.kind(of: space.kind),
                        isActive: space.id == display.currentSpaceID,
                        windows: windowSnapshots(onSpace: space.id, windowsByID: windowsByID)
                    )
                }
            )
        }

        return WorkspaceSnapshot(name: name, displays: displays)
    }

    /// Keeps the front-to-back order the WindowServer reports, which is what
    /// matching falls back to when titles are ambiguous.
    private func windowSnapshots(
        onSpace spaceID: SpaceID,
        windowsByID: [CGWindowID: LiveWindow]
    ) -> [WindowSnapshot] {
        spaces.windowIDs(onSpace: spaceID)
            .compactMap { windowsByID[$0] }
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
