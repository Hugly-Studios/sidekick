import AppKit
import Automation
import CoreGraphics
import PrivateAPI

/// Recreates a saved layout.
///
/// Order of operations is dictated by two macOS facts: new windows open on the
/// desktop that is active, and Accessibility only exposes windows of the visible
/// desktop. So apps are started first, then for every desktop in turn the app
/// goes there, moves the windows that belong there, and only then resizes them —
/// a window resized before the move gets clamped to the wrong desktop's geometry.
@MainActor
public struct SnapshotRestorer {
    private let spaces: any SpacesReading
    private let mover: any WindowSpaceMoving
    private let navigator: any SpaceNavigating
    private let inspector: WindowInspector
    private let arranger: WindowArranger
    private let launcher: AppLauncher

    public init(
        spaces: any SpacesReading,
        mover: any WindowSpaceMoving,
        navigator: any SpaceNavigating,
        inspector: WindowInspector = WindowInspector(),
        arranger: WindowArranger = WindowArranger(),
        launcher: AppLauncher = AppLauncher()
    ) {
        self.spaces = spaces
        self.mover = mover
        self.navigator = navigator
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
            let wasRunning = !NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).isEmpty

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

    private func restore(display: DisplaySnapshot, onto target: DisplaySpaces) async -> RestoreReport
    {
        var report = RestoreReport()

        let (candidates, live) = await survey(display: target, report: &report)

        // Matching happens once for the whole display: doing it per desktop would
        // let two desktops claim the same window.
        let entries = display.spaces.flatMap { space in space.windows.map { (space.index, $0) } }
        let pairs = WindowMatcher.pair(snapshots: entries.map(\.1), candidates: candidates)

        for space in display.spaces {
            guard let targetSpace = target.spaces.first(where: { $0.index == space.index }) else {
                report.problems.append(
                    "Рабочего стола №\(space.index) больше нет — создайте его в Mission Control")
                continue
            }

            var matched: [(snapshot: WindowSnapshot, window: LiveWindow)] = []

            for (offset, entry) in entries.enumerated() where entry.0 == space.index {
                guard let windowID = pairs[offset], let window = live[windowID] else {
                    report.problems.append("Окно «\(entry.1.appName)» не найдено")
                    continue
                }

                matched.append((entry.1, window))
            }

            guard !matched.isEmpty else { continue }

            do {
                try await navigator.activate(
                    spaceID: targetSpace.id, displayUUID: target.displayUUID)
            } catch {
                report.problems.append(error.localizedDescription)
                continue
            }

            report.merge(await move(matched, toSpace: targetSpace.id))

            for pair in matched {
                report.merge(apply(pair.snapshot, to: pair.window))
            }
        }

        await returnToActiveSpace(of: display, on: target, report: &report)

        return report
    }

    /// Collects every window that exists right now by visiting each desktop:
    /// Accessibility hides windows of desktops that are not visible, so without
    /// the walk most windows could not be identified at all.
    private func survey(
        display: DisplaySpaces,
        report: inout RestoreReport
    ) async -> ([MatchCandidate], [CGWindowID: LiveWindow]) {
        var candidates: [MatchCandidate] = []
        var live: [CGWindowID: LiveWindow] = [:]

        for space in display.spaces {
            do {
                try await navigator.activate(spaceID: space.id, displayUUID: display.displayUUID)
            } catch {
                report.problems.append(error.localizedDescription)
                continue
            }

            let identifiers = Set(spaces.windowIDs(onSpace: space.id))

            for window in (try? inspector.windows(withIDs: identifiers)) ?? []
            where live[window.id] == nil {
                live[window.id] = window
                candidates.append(
                    MatchCandidate(id: window.id, bundleID: window.bundleID, title: window.title))
            }
        }

        return (candidates, live)
    }

    private func returnToActiveSpace(
        of display: DisplaySnapshot,
        on target: DisplaySpaces,
        report: inout RestoreReport
    ) async {
        guard let activeIndex = display.spaces.first(where: \.isActive)?.index,
            let space = target.spaces.first(where: { $0.index == activeIndex })
        else { return }

        do {
            try await navigator.activate(spaceID: space.id, displayUUID: target.displayUUID)
        } catch {
            report.problems.append(error.localizedDescription)
        }
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
