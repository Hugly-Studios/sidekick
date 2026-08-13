import AppKit
import Automation
import CoreGraphics
import PrivateAPI

/// Recreates a saved layout.
///
/// Order of operations matters: apps are started first (their windows appear on
/// whatever desktop is active), then windows are moved to the desktop they belong
/// to, and only then resized — a window resized before the move gets clamped to
/// the wrong desktop's geometry.
@MainActor
public struct SnapshotRestorer {
    private let spaces: any SpacesReading
    private let mover: any WindowSpaceMoving
    private let inspector: WindowInspector
    private let arranger: WindowArranger
    private let launcher: AppLauncher

    public init(
        spaces: any SpacesReading,
        mover: any WindowSpaceMoving,
        inspector: WindowInspector = WindowInspector(),
        arranger: WindowArranger = WindowArranger(),
        launcher: AppLauncher = AppLauncher()
    ) {
        self.spaces = spaces
        self.mover = mover
        self.inspector = inspector
        self.arranger = arranger
        self.launcher = launcher
    }

    public func restore(_ snapshot: WorkspaceSnapshot, mode: RestoreMode) async -> RestoreReport {
        var report = RestoreReport()

        guard AccessibilityAuthorization.isGranted else {
            report.problems.append(AutomationError.accessibilityDenied.localizedDescription)
            return report
        }

        report.merge(await ensureApps(of: snapshot))

        let current = spaces.displays()

        for display in snapshot.displays {
            guard let target = current.first(where: { $0.displayUUID == display.uuid }) else {
                report.problems.append("Дисплей \(display.uuid) сейчас не подключён")
                continue
            }

            report.merge(await restore(display: display, onto: target))
        }

        if mode == .strict {
            report.quitApps = quitAppsOutside(snapshot)
        }

        report.finishedAt = Date()
        return report
    }

    // MARK: - Applications

    private func ensureApps(of snapshot: WorkspaceSnapshot) async -> RestoreReport {
        var report = RestoreReport()

        for bundleID in Self.bundleIDs(of: snapshot) {
            let wasRunning = !inspector.windows(ofBundleID: bundleID).isEmpty

            do {
                try await launcher.ensureWindows(bundleID: bundleID)
                if !wasRunning { report.launchedApps += 1 }
            } catch {
                report.problems.append(error.localizedDescription)
            }
        }

        return report
    }

    private static func bundleIDs(of snapshot: WorkspaceSnapshot) -> [String] {
        var seen = Set<String>()

        return snapshot.displays
            .flatMap(\.spaces)
            .flatMap(\.windows)
            .map(\.bundleID)
            .filter { seen.insert($0).inserted }
    }

    // MARK: - Layout

    /// Matching happens once for the whole display: doing it per desktop would let
    /// two desktops claim the same live window and the second move would undo the
    /// first.
    private func restore(display: DisplaySnapshot, onto target: DisplaySpaces) async -> RestoreReport
    {
        var report = RestoreReport()

        let live = (try? inspector.windows()) ?? []
        let liveByID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = display.spaces.flatMap { space in space.windows.map { (space.index, $0) } }
        let pairs = WindowMatcher.pair(
            snapshots: entries.map(\.1),
            candidates: live.map {
                MatchCandidate(id: $0.id, bundleID: $0.bundleID, title: $0.title)
            }
        )

        for space in display.spaces {
            guard let targetSpace = target.spaces.first(where: { $0.index == space.index }) else {
                report.problems.append(
                    "Рабочего стола №\(space.index) больше нет — создайте его в Mission Control")
                continue
            }

            var matched: [(snapshot: WindowSnapshot, window: LiveWindow)] = []

            for (offset, entry) in entries.enumerated() where entry.0 == space.index {
                guard let windowID = pairs[offset], let window = liveByID[windowID] else {
                    report.problems.append("Окно «\(entry.1.appName)» не найдено")
                    continue
                }

                matched.append((entry.1, window))
            }

            report.merge(await move(matched, toSpace: targetSpace.id))

            for pair in matched {
                report.merge(apply(pair.snapshot, to: pair.window))
            }
        }

        return report
    }

    /// Fullscreen windows own their own space and cannot be moved into another.
    private func move(
        _ matched: [(snapshot: WindowSnapshot, window: LiveWindow)],
        toSpace spaceID: SpaceID
    ) async -> RestoreReport {
        var report = RestoreReport()

        let movable = matched
            .filter { !$0.snapshot.isFullscreen }
            .map(\.window.id)
            .filter { !spaces.spaceIDs(ofWindow: $0).contains(spaceID) }

        guard !movable.isEmpty else { return report }

        do {
            try await mover.move(windowIDs: movable, toSpace: spaceID)
            report.movedWindows += movable.count
        } catch {
            report.problems.append(error.localizedDescription)
        }

        return report
    }

    private func apply(_ snapshot: WindowSnapshot, to window: LiveWindow) -> RestoreReport {
        var report = RestoreReport()

        do {
            if snapshot.isFullscreen {
                try arranger.setFullscreen(true, of: window)
            } else {
                if window.isFullscreen { try arranger.setFullscreen(false, of: window) }
                try arranger.setFrame(snapshot.frame.cgRect, of: window)
            }

            if snapshot.isMinimized != window.isMinimized {
                try arranger.setMinimized(snapshot.isMinimized, of: window)
            }

            report.arrangedWindows += 1
        } catch {
            report.problems.append("\(snapshot.appName): \(error.localizedDescription)")
        }

        return report
    }

    // MARK: - Strict mode

    /// Quits apps the snapshot does not mention. Only apps with a Dock presence
    /// are considered, so background helpers and agents are left alone.
    private func quitAppsOutside(_ snapshot: WorkspaceSnapshot) -> Int {
        let keep = Set(Self.bundleIDs(of: snapshot) + Self.neverQuit)
        let ownProcessID = ProcessInfo.processInfo.processIdentifier

        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.processIdentifier != ownProcessID }
            .filter { application in
                guard let bundleID = application.bundleIdentifier else { return false }
                return !keep.contains(bundleID)
            }
            .filter { $0.terminate() }
            .count
    }

    private static let neverQuit = [
        "com.apple.finder",
        "com.hugly.sidekick",
    ]
}
