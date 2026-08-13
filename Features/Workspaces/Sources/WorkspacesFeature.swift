import AppCore
import Automation
import Foundation
import Observation
import PrivateAPI
import SwiftUI

/// Saves and restores the whole desktop layout, and keeps desktops in order.
@MainActor
@Observable
public final class WorkspacesFeature: Feature {
    public static let descriptor = FeatureDescriptor(
        id: "workspaces",
        title: "Рабочие столы",
        summary: "Снимки столов, приложений и расположения окон с восстановлением после перезагрузки",
        symbolName: "rectangle.3.group",
        requiredPermissions: [.accessibility],
        isEnabledByDefault: false
    )

    public private(set) var snapshots: [WorkspaceSnapshot] = []
    public private(set) var lastReport: RestoreReport?
    public private(set) var isBusy = false

    public private(set) var restoreOnLogin: Bool
    public private(set) var defaultSnapshotID: UUID?
    public private(set) var mode: RestoreMode
    public private(set) var locksSpaceOrder: Bool

    public let orderGuard = SpaceOrderGuard()

    private let context: FeatureContext
    private let store: SnapshotStore
    private let spaces: SkyLightSpaces?
    private let inspector: WindowInspector
    private let capturer: SnapshotCapturer?
    private let restorer: SnapshotRestorer?

    public init(context: FeatureContext) {
        let spaces = SkyLightSpaces()
        let navigator = SkyLightSpaceNavigator()
        let inspector = WindowInspector()

        self.context = context
        self.store = SnapshotStore()
        self.spaces = spaces
        self.inspector = inspector

        if let spaces, let navigator {
            self.capturer = SnapshotCapturer(
                spaces: spaces, navigator: navigator, inspector: inspector)
            self.restorer = SnapshotRestorer(
                spaces: spaces, mover: spaces, navigator: navigator, inspector: inspector)
        } else {
            self.capturer = nil
            self.restorer = nil
        }

        self.restoreOnLogin = context.settings.value(for: Keys.restoreOnLogin)
        self.defaultSnapshotID = UUID(uuidString: context.settings.value(for: Keys.defaultSnapshot))
        self.mode =
            RestoreMode(rawValue: context.settings.value(for: Keys.mode)) ?? .additive
        self.locksSpaceOrder = context.settings.value(for: Keys.locksSpaceOrder)
    }

    // MARK: - Lifecycle

    /// Locking the desktop order needs no permission, so a missing Accessibility
    /// grant must not disable the whole module: it only blocks reading and moving
    /// windows, which the snapshot commands report when used.
    public func activate() async throws {
        guard spaces != nil else {
            throw FeatureActivationError.unsupportedSystem(
                "Управление рабочими столами недоступно на этой версии macOS")
        }

        reload()
        context.log.info("Activated, window access: \(self.hasWindowAccess, privacy: .public)")

        // Enabling the module is exactly when asking for the permission makes
        // sense; macOS shows this prompt at most once, then stays silent.
        if !hasWindowAccess {
            AccessibilityAuthorization.prompt()
        }

        if locksSpaceOrder {
            orderGuard.startWatching()
        }

        if context.launch.isLoginLaunch, restoreOnLogin, defaultSnapshot != nil {
            scheduleLoginRestore()
        }
    }

    public func deactivate() async {
        orderGuard.stopWatching()
    }

    public var commands: [Command] {
        [
            Command(id: "workspaces.capture", title: "Сохранить снимок столов", symbolName: "camera")
            {
                await self.capture(named: nil)
            },
            Command(
                id: "workspaces.restore",
                title: "Восстановить снимок",
                symbolName: "arrow.counterclockwise"
            ) {
                await self.restoreDefault()
            },
        ]
    }

    public func makeMenuView() -> AnyView? {
        AnyView(WorkspacesMenuView(feature: self))
    }

    public func makeSettingsView() -> AnyView {
        AnyView(WorkspacesSettingsView(feature: self))
    }

    // MARK: - Snapshots

    public var defaultSnapshot: WorkspaceSnapshot? {
        guard let defaultSnapshotID else { return snapshots.first }
        return snapshots.first { $0.id == defaultSnapshotID } ?? snapshots.first
    }

    public func reload() {
        snapshots = store.all()
    }

    public var hasWindowAccess: Bool {
        AccessibilityAuthorization.isGranted
    }

    /// What the app currently sees through Accessibility, for diagnostics.
    public func visibleWindowSummary() -> String {
        guard let windows = try? inspector.windows() else { return "окна недоступны" }

        let byApp = Dictionary(grouping: windows, by: \.appName)
            .map { "\($0.key): \($0.value.count)" }
            .sorted()

        return "окон видно \(windows.count) — \(byApp.joined(separator: ", "))"
    }

    /// Raw Accessibility numbers per app, for when a snapshot looks too empty.
    public func windowDiagnostics() -> [String] {
        inspector.diagnostics()
    }

    public func capture(named name: String?) async {
        guard let capturer else { return }

        guard hasWindowAccess else {
            lastReport = RestoreReport(
                problems: [AutomationError.accessibilityDenied.localizedDescription])
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let snapshot = try await capturer.capture(name: name ?? Self.defaultName())
            try store.save(snapshot)
            reload()

            if defaultSnapshotID == nil {
                setDefaultSnapshot(id: snapshot.id)
            }

            context.log.info("Captured snapshot with \(snapshot.windowCount) windows")
        } catch {
            context.log.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            lastReport = RestoreReport(problems: [error.localizedDescription])
        }
    }

    public func restore(id: UUID) async {
        guard let restorer, let snapshot = snapshots.first(where: { $0.id == id }) else { return }

        isBusy = true
        defer { isBusy = false }

        lastReport = await restorer.restore(snapshot, mode: mode)
        context.log.info("Restore finished: \(self.lastReport?.summary ?? "", privacy: .public)")
    }

    public func restoreDefault() async {
        guard let snapshot = defaultSnapshot else { return }
        await restore(id: snapshot.id)
    }

    public func delete(id: UUID) {
        try? store.delete(id: id)

        if defaultSnapshotID == id {
            setDefaultSnapshot(id: nil)
        }

        reload()
    }

    /// True when desktops are no longer in the order the snapshot recorded.
    public func spaceOrderDrifted() -> Bool {
        guard let spaces, let snapshot = defaultSnapshot else { return false }

        let current = spaces.displays().flatMap(\.spaces).compactMap(\.uuid)
        let saved = snapshot.spaceOrder

        guard !saved.isEmpty, Set(current) == Set(saved) else { return false }

        return current != saved
    }

    // MARK: - Settings

    public func setRestoreOnLogin(_ value: Bool) {
        restoreOnLogin = value
        context.settings.set(value, for: Keys.restoreOnLogin)
    }

    public func setDefaultSnapshot(id: UUID?) {
        defaultSnapshotID = id
        context.settings.set(id?.uuidString ?? "", for: Keys.defaultSnapshot)
    }

    public func setMode(_ value: RestoreMode) {
        mode = value
        context.settings.set(value.rawValue, for: Keys.mode)
    }

    public func setLocksSpaceOrder(_ value: Bool) {
        locksSpaceOrder = value
        context.settings.set(value, for: Keys.locksSpaceOrder)

        if value {
            orderGuard.startWatching()
        } else {
            orderGuard.stopWatching()
        }
    }

    // MARK: - Login restore

    /// At login the system is still opening its own login items and reopening
    /// windows; restoring into that churn moves windows that are about to move
    /// again, so the layout is applied once things settle.
    private func scheduleLoginRestore() {
        Task { [weak self] in
            try? await Task.sleep(for: Self.loginSettleDelay)
            await self?.restoreDefault()
        }
    }

    private static func defaultName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM, HH:mm"
        return formatter.string(from: Date())
    }

    private static let loginSettleDelay = Duration.seconds(15)

    private enum Keys {
        static let restoreOnLogin = SettingKey("restoreOnLogin", default: false)
        static let defaultSnapshot = SettingKey("defaultSnapshotID", default: "")
        static let mode = SettingKey("restoreMode", default: RestoreMode.additive.rawValue)
        static let locksSpaceOrder = SettingKey("locksSpaceOrder", default: true)
    }
}
