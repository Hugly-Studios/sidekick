import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginController {
    /// Label of the embedded launch agent. A login launch is recognised by it, so
    /// it must match Apps/Mac/LaunchAgents/com.hugly.sidekick.login.plist.
    nonisolated static let agentLabel = "com.hugly.sidekick.login"

    nonisolated static let plistName = "\(agentLabel).plist"

    private(set) var isEnabled: Bool
    private(set) var failure: String?

    private var service: SMAppService { SMAppService.agent(plistName: Self.plistName) }

    init() {
        isEnabled = SMAppService.agent(plistName: Self.plistName).status == .enabled
        migrateFromPlainLoginItem()
    }

    func refresh() {
        isEnabled = service.status == .enabled
    }

    func setEnabled(_ newValue: Bool) {
        do {
            if newValue {
                try service.register()
            } else {
                try service.unregister()
            }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }

        refresh()
    }

    /// Earlier versions registered the app itself as a login item; that
    /// registration would start a second copy at login.
    private func migrateFromPlainLoginItem() {
        guard SMAppService.mainApp.status == .enabled else { return }

        try? SMAppService.mainApp.unregister()
        setEnabled(true)
    }
}
