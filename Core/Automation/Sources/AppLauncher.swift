import AppKit

/// Starts applications a snapshot needs and waits until they have windows.
@MainActor
public struct AppLauncher {
    private let inspector: WindowInspector

    public init(inspector: WindowInspector = WindowInspector()) {
        self.inspector = inspector
    }

    /// Launches the app unless it is already running, then waits for its windows.
    ///
    /// Launching without activation keeps the restore from stealing focus window
    /// by window, and new windows open on whatever space is active — the caller
    /// moves them afterwards.
    public func ensureWindows(
        bundleID: String,
        timeout: Duration = .seconds(20)
    ) async throws {
        if inspector.hasWindowsAnywhere(bundleID: bundleID) { return }

        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            try await launch(bundleID: bundleID)
        }

        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if inspector.hasWindowsAnywhere(bundleID: bundleID) { return }
            try await Task.sleep(for: .milliseconds(200))
        }

        throw AutomationError.applicationDidNotOpenWindows(bundleID: bundleID)
    }

    private func launch(bundleID: String) async throws {
        guard
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            throw AutomationError.applicationNotFound(bundleID: bundleID)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false

        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
