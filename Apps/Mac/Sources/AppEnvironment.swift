import AppCore
import HotkeysKit
import OSLog
import Observation
import PermissionsKit
import Workspaces

/// Wires the kernel together and holds the list of features the app ships with.
@MainActor
@Observable
final class AppEnvironment {
    let settings: any SettingsStore
    let events: EventBus
    let commands: CommandRegistry
    let features: FeatureRegistry
    let permissions: LivePermissionChecker
    let launchAtLogin: LaunchAtLoginController
    let hotkeys: HotkeyService

    init() {
        let log = AppLog.make(category: "app")
        let settings = UserDefaultsSettingsStore()
        let events = EventBus()
        let commands = CommandRegistry(log: log)
        let permissions = LivePermissionChecker()

        self.settings = settings
        self.events = events
        self.commands = commands
        self.permissions = permissions
        self.launchAtLogin = LaunchAtLoginController()
        self.hotkeys = HotkeyService()
        self.features = FeatureRegistry(
            featureTypes: Self.featureTypes,
            settings: settings,
            events: events,
            commands: commands,
            log: log,
            launch: LaunchContext(isLoginLaunch: AppInstance.wasLaunchedByLaunchd),
            permissions: permissions
        )
    }

    /// The single place where a new feature module is plugged in.
    /// See docs/adding-a-feature.md.
    static var featureTypes: [any Feature.Type] {
        [WorkspacesFeature.self]
    }
}
