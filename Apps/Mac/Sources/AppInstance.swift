import AppKit
import Foundation

/// Guards against two copies of Sidekick running at once.
///
/// Installing over an old copy, or running a debug build next to the one in
/// /Applications, would otherwise leave two instances fighting over the menu bar
/// icon and the same settings domain.
enum AppInstance {
    private static let showPanelNotification = Notification.Name("com.hugly.sidekick.showPanel")

    /// True when the embedded launch agent started this process, i.e. at login.
    ///
    /// The obvious check — "was I started by launchd" — is useless: every GUI
    /// launch goes through launchd and gets an XPC_SERVICE_NAME of
    /// `application.<bundle id>.<hash>`, so opening the app by hand looked exactly
    /// like a login. An agent's process carries the agent's label instead.
    static var wasLaunchedByLaunchd: Bool {
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"]
            == LaunchAtLoginController.agentLabel
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
