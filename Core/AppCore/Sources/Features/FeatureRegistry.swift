import OSLog
import Observation

/// Owns feature instances, their enabled state and their lifecycle.
@MainActor
@Observable
public final class FeatureRegistry {
    public struct Entry: Identifiable {
        public let descriptor: FeatureDescriptor
        public internal(set) var isEnabled: Bool
        /// Reason the feature could not activate, shown next to it in the UI.
        public internal(set) var failure: String?

        public let feature: any Feature

        public var id: FeatureID { descriptor.id }
    }

    public private(set) var entries: [Entry] = []

    private let settings: any SettingsStore
    private let commands: CommandRegistry
    private let permissions: any PermissionChecking
    private let log: Logger

    public init(
        featureTypes: [any Feature.Type],
        settings: any SettingsStore,
        events: EventBus,
        commands: CommandRegistry,
        log: Logger,
        launch: LaunchContext = LaunchContext(isLoginLaunch: false),
        permissions: any PermissionChecking = UncheckedPermissions()
    ) {
        self.settings = settings
        self.commands = commands
        self.permissions = permissions
        self.log = log

        entries = featureTypes.map { featureType in
            let descriptor = featureType.descriptor
            let context = FeatureContext(
                id: descriptor.id,
                settings: settings.namespaced(Self.settingsNamespace(for: descriptor.id)),
                events: events,
                log: AppLog.make(category: descriptor.id.rawValue),
                launch: launch
            )

            return Entry(
                descriptor: descriptor,
                isEnabled: settings.value(for: Self.enabledKey(for: descriptor)),
                feature: featureType.init(context: context)
            )
        }
    }

    /// Activates every enabled feature. Called once when the app finishes launching.
    public func start() async {
        for index in entries.indices where entries[index].isEnabled {
            await activate(at: index)
        }
    }

    public func stop() async {
        for entry in entries where entry.isEnabled {
            commands.unregister(owner: entry.id)
            await entry.feature.deactivate()
        }
    }

    public func setEnabled(_ isEnabled: Bool, for id: FeatureID) async {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }

        entries[index].isEnabled = isEnabled
        settings.set(isEnabled, for: Self.enabledKey(for: entries[index].descriptor))

        if isEnabled {
            await activate(at: index)
        } else {
            entries[index].failure = nil
            commands.unregister(owner: id)
            await entries[index].feature.deactivate()
        }
    }

    public func entry(for id: FeatureID) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Typed access to a feature instance, for surfaces that need more than the
    /// generic command list.
    public func feature<Concrete: Feature>(_ type: Concrete.Type) -> Concrete? {
        entries.compactMap { $0.feature as? Concrete }.first
    }

    private func activate(at index: Int) async {
        let entry = entries[index]

        do {
            try await ensurePermissions(for: entry.descriptor)
            try await entry.feature.activate()
            entries[index].failure = nil
            commands.register(entry.feature.commands, owner: entry.id)
        } catch {
            entries[index].failure = error.localizedDescription
            commands.unregister(owner: entry.id)
            log.error(
                "Feature \(entry.id.rawValue, privacy: .public) failed to activate: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func ensurePermissions(for descriptor: FeatureDescriptor) async throws {
        for permission in descriptor.requiredPermissions {
            var status = permissions.status(of: permission)
            if status != .granted {
                status = await permissions.request(permission)
            }

            if status != .granted {
                throw FeatureActivationError.missingPermission(permission)
            }
        }
    }

    /// Public so other entry points (CLI, diagnostics) read the same settings a
    /// running feature does.
    public static func settingsNamespace(for id: FeatureID) -> String {
        "features.\(id.rawValue)"
    }

    private static func enabledKey(for descriptor: FeatureDescriptor) -> SettingKey<Bool> {
        SettingKey(
            "\(settingsNamespace(for: descriptor.id)).enabled",
            default: descriptor.isEnabledByDefault
        )
    }
}
