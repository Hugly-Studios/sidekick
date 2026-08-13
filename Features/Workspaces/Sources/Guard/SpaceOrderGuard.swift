import Foundation
import Observation

/// Keeps desktops in the order the user arranged them.
///
/// macOS ships with "Automatically rearrange Spaces based on most recent use"
/// enabled, which silently reorders desktops as you switch between them — that is
/// the actual cause of a layout drifting away from a snapshot. The setting lives
/// in the Dock's preferences and only takes effect after the Dock restarts.
@MainActor
@Observable
public final class SpaceOrderGuard {
    public private(set) var isAutoRearrangeDisabled: Bool
    public private(set) var lastEnforcedAt: Date?

    private let dockDefaults: UserDefaults?
    private var watchTask: Task<Void, Never>?

    public init() {
        dockDefaults = UserDefaults(suiteName: Self.dockDomain)
        isAutoRearrangeDisabled = false
        refresh()
    }

    public func refresh() {
        // An absent value means the macOS default, which is "rearrange".
        isAutoRearrangeDisabled = dockDefaults?.object(forKey: Self.key) as? Bool == false
    }

    /// Applies the setting if needed and reports whether the Dock had to restart.
    @discardableResult
    public func enforce() -> Bool {
        refresh()
        guard !isAutoRearrangeDisabled else { return false }

        dockDefaults?.set(false, forKey: Self.key)
        dockDefaults?.synchronize()
        restartDock()
        lastEnforcedAt = Date()
        refresh()

        return true
    }

    /// Re-checks periodically: System Settings, another tool or a migration can
    /// switch the option back on at any time.
    public func startWatching(interval: Duration = .seconds(60)) {
        enforce()
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.enforce()
            }
        }
    }

    public func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    /// Lets the user opt out without leaving the Dock in a half-configured state.
    public func allowAutoRearrange() {
        dockDefaults?.set(true, forKey: Self.key)
        dockDefaults?.synchronize()
        restartDock()
        refresh()
    }

    private func restartDock() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }

    private static let dockDomain = "com.apple.dock"
    private static let key = "mru-spaces"
}
