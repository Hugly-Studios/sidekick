import AppCore
import AppKit
import ControlSurface
import HotkeysKit
import SwiftUI

@main
enum SidekickMain {
    @MainActor
    static func main() {
        if ControlCommandLine.run(arguments: CommandLine.arguments) {
            return
        }

        guard !AppInstance.handOverToRunningInstance() else { return }

        SidekickApp.main()
    }
}

struct SidekickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView(environment: appDelegate.environment)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    lazy var settingsWindow = SettingsWindowController()

    private var controlServer: ControlServer?
    private var menuBar: MenuBarController?
    private static let hasShownWelcomeKey = SettingKey("hasShownWelcome", default: false)

    func applicationDidFinishLaunching(_: Notification) {
        menuBar = MenuBarController(
            environment: environment,
            settingsWindow: settingsWindow
        )
        startControlServer()

        Task {
            await environment.features.start()
        }

        environment.hotkeys.bind(Hotkeys.openPanel) { [weak self] in
            self?.settingsWindow.show()
        }

        AppInstance.observeShowPanelRequests { [weak self] in
            self?.settingsWindow.show()
        }

        showWelcomeWindowIfNeeded()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        settingsWindow.show()
        return true
    }

    func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        Task {
            controlServer?.stop()
            await environment.features.stop()
            application.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    private func startControlServer() {
        let handler = AppControlHandler(
            environment: environment,
            permissions: environment.permissions,
            menuBar: menuBar
        )

        let server = ControlServer(handler: handler)
        do {
            try server.start()
            controlServer = server
        } catch {
            AppLog.make(category: "control").error(
                "Control server failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func showWelcomeWindowIfNeeded() {
        guard !AppInstance.wasLaunchedByLaunchd,
            !environment.settings.value(for: Self.hasShownWelcomeKey)
        else { return }

        environment.settings.set(true, for: Self.hasShownWelcomeKey)
        settingsWindow.show()
    }
}
