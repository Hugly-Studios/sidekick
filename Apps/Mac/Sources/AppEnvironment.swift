import AppCore
import OSLog
import Observation

/// Wires the kernel together and holds the list of features the app ships with.
@MainActor
@Observable
final class AppEnvironment {
    let settings: any SettingsStore
    let events: EventBus
    let commands: CommandRegistry
    let features: FeatureRegistry
    let launchAtLogin: LaunchAtLoginController

    init() {
        let log = AppLog.make(category: "app")
        let settings = UserDefaultsSettingsStore()
        let events = EventBus()
        let commands = CommandRegistry(log: log)

        self.settings = settings
        self.events = events
        self.commands = commands
        self.launchAtLogin = LaunchAtLoginController()
        self.features = FeatureRegistry(
            featureTypes: Self.featureTypes,
            settings: settings,
            events: events,
            commands: commands,
            log: log
        )
    }

    /// The single place where a new feature module is plugged in.
    /// See docs/adding-a-feature.md.
    static var featureTypes: [any Feature.Type] {
        []
    }
}
