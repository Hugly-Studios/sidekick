import AppCore
import Foundation
import OSLog

public enum TestFeatureContext {
    @MainActor
    public static func make(
        id: FeatureID = "test",
        settings: any SettingsStore = InMemorySettingsStore()
    ) -> FeatureContext {
        FeatureContext(
            id: id,
            settings: settings.namespaced(FeatureRegistry.settingsNamespace(for: id)),
            events: EventBus(),
            log: Logger(subsystem: "com.hugly.sidekick.tests", category: id.rawValue),
            launch: LaunchContext(isLoginLaunch: false)
        )
    }
}
