import AppCore
import AppKit
import ControlSurface
import Foundation
import PermissionsKit

@MainActor
final class AppControlHandler: ControlHandling {
    private let environment: AppEnvironment
    private let permissions: LivePermissionChecker

    init(environment: AppEnvironment, permissions: LivePermissionChecker) {
        self.environment = environment
        self.permissions = permissions
    }

    func status() async -> StatusPayload {
        let info = Bundle.main.infoDictionary
        return StatusPayload(
            version: info?["CFBundleShortVersionString"] as? String ?? "?",
            build: info?["CFBundleVersion"] as? String ?? "?",
            path: Bundle.main.bundleURL.path,
            pid: ProcessInfo.processInfo.processIdentifier,
            features: listFeatures()
        )
    }

    func listFeatures() -> [FeatureInfo] {
        environment.features.entries.map { entry in
            FeatureInfo(
                id: entry.id.rawValue,
                title: entry.descriptor.title,
                enabled: entry.isEnabled,
                failure: entry.failure
            )
        }
    }

    func setFeature(id: String, enabled: Bool) async throws -> FeatureInfo {
        let featureID = FeatureID(rawValue: id)
        guard environment.features.entry(for: featureID) != nil else {
            throw ControlHandlerError.featureNotFound(id)
        }

        await environment.features.setEnabled(enabled, for: featureID)
        guard let entry = environment.features.entry(for: featureID) else {
            throw ControlHandlerError.featureNotFound(id)
        }

        return FeatureInfo(
            id: entry.id.rawValue,
            title: entry.descriptor.title,
            enabled: entry.isEnabled,
            failure: entry.failure
        )
    }

    func listCommands() -> [CommandInfo] {
        environment.commands.entries.map { entry in
            CommandInfo(
                id: entry.command.id.rawValue,
                title: entry.command.title,
                owner: entry.owner.rawValue
            )
        }
    }

    func run(commandID: String, argument: String?) async throws -> String {
        try await environment.commands.run(CommandID(rawValue: commandID), argument: argument)
    }

    func settingsGet(_ key: String) -> String? {
        environment.settings.inspect(key)
    }

    func settingsSet(_ key: String, _ value: String) {
        environment.settings.write(key, value: value)
    }

    func logs(sinceSeconds: Double, level: String?) throws -> [LogRecord] {
        try LogReader.fetch(since: sinceSeconds, level: level)
    }

    func doctor() async -> DoctorPayload {
        await DoctorReport.build(environment: environment, permissions: permissions)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
