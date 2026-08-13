import AppKit
import HotkeysKit
import ServiceManagement

/// Prints how this copy of Sidekick is installed and whether it is reachable.
///
/// Exists because the failure modes of a menu bar app are invisible: an ad-hoc
/// signature silently drops permission grants on every rebuild, and a full menu
/// bar on a notched Mac hides the icon entirely.
@MainActor
enum Doctor {
    static func run() {
        print("Sidekick doctor")
        print("")

        bundleSection()
        signingSection()
        loginItemSection()
        reachabilitySection()
        permissionsSection()
    }

    private static func bundleSection() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        print("bundle")
        line("id", Bundle.main.bundleIdentifier ?? "?")
        line("version", "\(version) (\(build))")
        line("path", Bundle.main.bundleURL.path)
        line("launched by launchd", AppInstance.wasLaunchedByLaunchd ? "yes" : "no")

        let running =
            NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        line("other running copies", running.isEmpty ? "none" : "\(running.count)")
        for application in running {
            line("  copy", application.bundleURL?.path ?? "unknown path")
        }
        print("")
    }

    private static func signingSection() {
        print("code signature")

        var staticCode: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode)
                == errSecSuccess,
            let staticCode
        else {
            line("state", "unreadable")
            print("")
            return
        }

        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &information
            )
                == errSecSuccess,
            let details = information as? [String: Any]
        else {
            line("state", "unreadable")
            print("")
            return
        }

        let flags = details[kSecCodeInfoFlags as String] as? UInt32 ?? 0
        let isAdHoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0

        line("team", details[kSecCodeInfoTeamIdentifier as String] as? String ?? "none")
        line("kind", isAdHoc ? "ad-hoc" : "identity")

        if isAdHoc {
            warn(
                "ad-hoc signatures change on every build, so macOS drops granted permissions",
                fix: "cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig"
            )
        }
        print("")
    }

    private static func loginItemSection() {
        print("login item")

        let status = SMAppService.mainApp.status
        let description =
            switch status {
            case .enabled: "enabled"
            case .requiresApproval: "requires approval in System Settings"
            case .notRegistered: "not registered"
            case .notFound: "not found"
            @unknown default: "unknown"
            }

        line("status", description)
        print("")
    }

    private static func reachabilitySection() {
        print("reachability")

        let shortcut = HotkeyService.shortcutDescription(for: Hotkeys.openPanel)
        line("open panel shortcut", shortcut ?? "not set")

        if shortcut == nil {
            warn(
                "without a shortcut the app is only reachable through the menu bar icon",
                fix: "set it in Sidekick settings, section General"
            )
        }

        switch menuBarIconPlacement() {
        case .visible(let x):
            line("menu bar icon", "visible at x=\(Int(x))")
        case .behindNotch(let x, let notch):
            line("menu bar icon", "hidden at x=\(Int(x))")
            warn(
                "the menu bar is full, so the icon sits behind the notch (x \(Int(notch.lowerBound))-\(Int(notch.upperBound)))",
                fix: "free space right of the notch, or use the shortcut above"
            )
        case .unknown:
            line("menu bar icon", "could not measure")
        }
        print("")
    }

    /// Asks the running app rather than trusting this process: permissions are
    /// attributed to whoever started the binary, so a copy launched from a terminal
    /// reports the terminal's access, not the app's.
    private static func permissionsSection() {
        print("permissions")

        guard RemoteControl.isAppRunning,
            let reply = RemoteControl.send(.status, timeout: 15)
        else {
            line("accessibility", AXIsProcessTrusted() ? "granted" : "not granted")
            warn(
                "measured for this terminal-started process, which is not what the app itself has",
                fix: "open Sidekick, then run make doctor again"
            )
            print("")
            return
        }

        for reportedLine in reply.split(separator: "\n") {
            print("  \(reportedLine)")
        }
        print("")
    }

    // MARK: - Menu bar measurement

    private enum IconPlacement {
        case visible(x: CGFloat)
        case behindNotch(x: CGFloat, notch: ClosedRange<CGFloat>)
        case unknown
    }

    /// Places a temporary status item to find out where the system would put ours.
    private static func menuBarIconPlacement() -> IconPlacement {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: nil
        )

        defer { NSStatusBar.system.removeStatusItem(item) }

        guard let frame = placedFrame(of: item) else { return .unknown }

        guard let screen = NSScreen.main,
            let leftArea = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        else {
            // No notch on this display, so a placed item is a visible item.
            return .visible(x: frame.minX)
        }

        let notch = leftArea.maxX...rightArea.minX

        return notch.contains(frame.midX)
            ? .behindNotch(x: frame.minX, notch: notch)
            : .visible(x: frame.minX)
    }

    /// Waits until AppKit actually places the item in the bar.
    ///
    /// Until then the button's window still sits at its default origin, which
    /// would read as a perfectly visible x=0 and hide the very problem this
    /// check exists to find.
    private static func placedFrame(of item: NSStatusItem) -> CGRect? {
        let deadline = Date().addingTimeInterval(2)

        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))

            if let frame = item.button?.window?.frame, frame.minX > 0, frame.width > 0 {
                return frame
            }
        }

        return nil
    }

    // MARK: - Output

    private static func line(_ label: String, _ value: String) {
        print("  \(label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(value)")
    }

    private static func warn(_ problem: String, fix: String) {
        print("  ! \(problem)")
        print("    fix: \(fix)")
    }
}
