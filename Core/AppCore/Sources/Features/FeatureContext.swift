import OSLog

/// Dependencies handed to a feature at construction time.
///
/// Everything system-facing arrives through this context, which is what keeps
/// feature logic testable without Accessibility, XPC or private APIs.
public struct FeatureContext: Sendable {
    public let id: FeatureID

    /// Already namespaced under the feature id, so keys cannot collide.
    public let settings: any SettingsStore

    public let events: EventBus
    public let log: Logger
    public let launch: LaunchContext

    public init(
        id: FeatureID,
        settings: any SettingsStore,
        events: EventBus,
        log: Logger,
        launch: LaunchContext
    ) {
        self.id = id
        self.settings = settings
        self.events = events
        self.log = log
        self.launch = launch
    }
}
