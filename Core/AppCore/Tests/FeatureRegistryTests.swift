import Foundation
import SwiftUI
import Testing

@testable import AppCore

/// Stub whose activation outcome is driven by its own namespaced settings,
/// which is also how a real feature reads configuration.
@MainActor
private final class StubFeature: Feature {
    static let descriptor = FeatureDescriptor(
        id: "stub",
        title: "Stub",
        summary: "Test double",
        symbolName: "hammer",
        isEnabledByDefault: true
    )

    static let shouldFailKey = SettingKey("shouldFail", default: false)

    private let context: FeatureContext

    init(context: FeatureContext) {
        self.context = context
    }

    func activate() async throws {
        if context.settings.value(for: Self.shouldFailKey) {
            throw FeatureActivationError.missingPermission(.accessibility)
        }
    }

    func deactivate() async {}

    var commands: [Command] {
        [Command(id: "stub.run", title: "Run") {}]
    }

    func makeSettingsView() -> AnyView {
        AnyView(EmptyView())
    }
}

@MainActor
struct FeatureRegistryTests {
    private func makeRegistry(shouldFail: Bool = false) -> (FeatureRegistry, CommandRegistry) {
        let defaults = UserDefaults(suiteName: "sidekick.tests.\(UUID().uuidString)")!
        let settings = UserDefaultsSettingsStore(defaults: defaults)

        if shouldFail {
            settings
                .namespaced("features.stub")
                .set(true, for: StubFeature.shouldFailKey)
        }

        let commands = CommandRegistry(log: AppLog.make(category: "tests"))
        let registry = FeatureRegistry(
            featureTypes: [StubFeature.self],
            settings: settings,
            events: EventBus(),
            commands: commands,
            log: AppLog.make(category: "tests")
        )

        return (registry, commands)
    }

    @Test func activatesEnabledFeatureAndRegistersItsCommands() async {
        let (registry, commands) = makeRegistry()

        await registry.start()

        #expect(registry.entry(for: "stub")?.isEnabled == true)
        #expect(registry.entry(for: "stub")?.failure == nil)
        #expect(commands.commands(of: "stub").count == 1)
    }

    @Test func recordsFailureAndKeepsCommandsUnregistered() async {
        let (registry, commands) = makeRegistry(shouldFail: true)

        await registry.start()

        #expect(registry.entry(for: "stub")?.failure != nil)
        #expect(commands.commands(of: "stub").isEmpty)
    }

    @Test func disablingRemovesCommands() async {
        let (registry, commands) = makeRegistry()
        await registry.start()

        await registry.setEnabled(false, for: "stub")

        #expect(registry.entry(for: "stub")?.isEnabled == false)
        #expect(commands.commands(of: "stub").isEmpty)
    }

    @Test func enabledStatePersistsInSettings() async {
        let defaults = UserDefaults(suiteName: "sidekick.tests.\(UUID().uuidString)")!
        let settings = UserDefaultsSettingsStore(defaults: defaults)
        let makeRegistry = {
            FeatureRegistry(
                featureTypes: [StubFeature.self],
                settings: settings,
                events: EventBus(),
                commands: CommandRegistry(log: AppLog.make(category: "tests")),
                log: AppLog.make(category: "tests")
            )
        }

        await makeRegistry().setEnabled(false, for: "stub")

        #expect(makeRegistry().entry(for: "stub")?.isEnabled == false)
    }
}
