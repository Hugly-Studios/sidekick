import AppKit
import Foundation

/// Guards against two copies of Sidekick running at once.
///
/// Installing over an old copy, or running a debug build next to the one in
/// /Applications, would otherwise leave two instances fighting over the menu bar
/// icon and the same settings domain.
enum AppInstance {
    private static let showPanelNotification = Notification.Name("com.hugly.sidekick.showPanel")

    /// True when this process was started by launchd, which is how a login item
    /// is launched — as opposed to the user opening the app.
    static var wasLaunchedByLaunchd: Bool {
        let serviceName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] ?? "0"
        return !serviceName.isEmpty && serviceName != "0"
    }

    /// Asks an already running instance to show its window and reports whether
    /// this process should exit instead of starting up.
    static func handOverToRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others =
            NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        guard !others.isEmpty else { return false }

        DistributedNotificationCenter.default().postNotificationName(
            showPanelNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        return true
    }

    static func observeShowPanelRequests(_ handler: @escaping @MainActor () -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: showPanelNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}
