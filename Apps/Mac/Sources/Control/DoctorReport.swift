import AppCore
import ControlSurface
import Foundation
import HotkeysKit
import PermissionsKit
import Security
import ServiceManagement

enum DoctorReport {
    @MainActor
    static func build(
        environment: AppEnvironment?,
        permissions: LivePermissionChecker
    ) async -> DoctorPayload {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let signing = signingInfo()
        let login = loginItemStatus()
        let shortcut = HotkeyService.shortcutDescription(for: Hotkeys.openPanel)

        var warnings: [String] = []
        if signing.kind == "ad-hoc" {
            warnings.append(
                "ad-hoc signatures change on every build, so macOS drops granted permissions"
            )
        }
        if shortcut == nil {
            warnings.append(
                "without a shortcut the app is only reachable through the menu bar icon"
            )
        }

        var permissionInfos: [PermissionInfo] = []
        for kind in PermissionKind.allCases {
            let status: PermissionStatus =
                if kind == .notifications {
                    await permissions.notificationStatus()
                } else {
                    permissions.status(of: kind)
                }

            permissionInfos.append(
                PermissionInfo(
                    id: kind.rawValue,
                    title: kind.title,
                    status: status.rawValue,
                    settingsURL: kind.settingsURL
                )
            )
        }

        return DoctorPayload(
            bundleID: Bundle.main.bundleIdentifier ?? "com.hugly.sidekick",
            version: version,
            build: build,
            path: Bundle.main.bundleURL.path,
            teamID: signing.team,
            signingKind: signing.kind,
            loginItem: login,
            shortcut: shortcut,
            // Left to the CLI: see MenuBarIconProbe.
            menuBarIcon: "",
            permissions: permissionInfos,
            warnings: warnings,
            running: environment != nil
        )
    }

    static func signingInfo() -> (team: String?, kind: String) {
        var staticCode: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode)
                == errSecSuccess,
            let staticCode
        else { return (nil, "unreadable") }

        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &information
            ) == errSecSuccess,
            let details = information as? [String: Any]
        else { return (nil, "unreadable") }

        let flags = details[kSecCodeInfoFlags as String] as? UInt32 ?? 0
        let isAdHoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0
        let team = details[kSecCodeInfoTeamIdentifier as String] as? String

        return (team, isAdHoc ? "ad-hoc" : "identity")
    }

    static func loginItemStatus() -> String {
        let status = SMAppService.agent(plistName: LaunchAtLoginController.plistName).status
        return switch status {
        case .enabled: "enabled"
        case .requiresApproval: "requires approval in System Settings"
        case .notRegistered: "not registered"
        case .notFound: "not found"
        @unknown default: "unknown"
        }
    }
}
