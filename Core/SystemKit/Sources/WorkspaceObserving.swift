import AppKit
import Foundation

public struct WorkspaceLaunchEvent: Sendable {
    public let bundleID: String
    public let isLaunch: Bool

    public init(bundleID: String, isLaunch: Bool) {
        self.bundleID = bundleID
        self.isLaunch = isLaunch
    }
}

/// Frontmost app and launch/quit events without talking to AppKit from a feature.
public protocol WorkspaceObserving: Sendable {
    var frontmostBundleID: String? { get }
    var runningBundleIDs: [String] { get }
    func events() -> AsyncStream<WorkspaceLaunchEvent>
}

public struct LiveWorkspaceObserver: WorkspaceObserving {
    public init() {}

    public var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public var runningBundleIDs: [String] {
        NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    }

    public func events() -> AsyncStream<WorkspaceLaunchEvent> {
        AsyncStream { continuation in
            let workspace = NSWorkspace.shared
            let launch = workspace.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: nil
            ) { notification in
                guard
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                    let bundleID = app.bundleIdentifier
                else { return }

                continuation.yield(WorkspaceLaunchEvent(bundleID: bundleID, isLaunch: true))
            }

            let quit = workspace.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: nil
            ) { notification in
                guard
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                    let bundleID = app.bundleIdentifier
                else { return }

                continuation.yield(WorkspaceLaunchEvent(bundleID: bundleID, isLaunch: false))
            }

            nonisolated(unsafe) let launchObserver = launch
            nonisolated(unsafe) let quitObserver = quit
            continuation.onTermination = { _ in
                NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
                NSWorkspace.shared.notificationCenter.removeObserver(quitObserver)
            }
        }
    }
}
