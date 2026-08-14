import AppCore
import ControlSurface
import Foundation
import PermissionsKit

/// Compatibility wrapper used by the CLI and the control handler.
enum Doctor {
    static func offline() -> DoctorPayload {
        let signing = DoctorReport.signingInfo()
        return DoctorPayload(
            bundleID: Bundle.main.bundleIdentifier ?? "com.hugly.sidekick",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            path: Bundle.main.bundleURL.path,
            teamID: signing.team,
            signingKind: signing.kind,
            loginItem: DoctorReport.loginItemStatus(),
            shortcut: nil,
            // Left to the CLI: see MenuBarIconProbe.
            menuBarIcon: "",
            permissions: [],
            warnings: [
                "приложение не запущено — разрешения процесса терминала здесь не считаются"
            ],
            running: false
        )
    }
}
