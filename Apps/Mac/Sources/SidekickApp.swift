import AppCore
import AppKit
import HotkeysKit
import SwiftUI

@main
enum SidekickMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--doctor") {
            Doctor.run()
            return
        }

        if WorkspacesCommandLine.run(arguments: CommandLine.arguments) {
            return
        }

        guard !AppInstance.handOverToRunningInstance() else { return }

        SidekickApp.main()
    }
}

struct SidekickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Sidekick", systemImage: "square.grid.2x2") {
            MenuBarContent(
                environment: appDelegate.environment,
                settingsWindow: appDelegate.settingsWindow
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    lazy var settingsWindow = SettingsWindowController(environment: environment)

    private static let hasShownWelcomeKey = SettingKey("hasShownWelcome", default: false)

    func applicationDidFinishLaunching(_: Notification) {
        Task {
            await environment.features.start()
            WorkspacesRemoteHandler.install(features: environment.features)
        }

        environment.hotkeys.bind(Hotkeys.openPanel) { [weak self] in
            self?.settingsWindow.show()
        }

        AppInstance.observeShowPanelRequests { [weak self] in
            self?.settingsWindow.show()
        }

        showWelcomeWindowIfNeeded()
    }

    /// Launching the app again is the reliable way back in when the menu bar icon
    /// is not reachable, so the window is shown regardless of other open windows.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        settingsWindow.show()
        return true
    }

    /// Gives features a real async shutdown hook instead of racing termination.
    func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await environment.features.stop()
            application.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    /// The menu bar icon can be unreachable (a full menu bar on a notched Mac hides
    /// new status items), so the first manual launch always shows a real window.
    /// Starting at login must stay silent.
    private func showWelcomeWindowIfNeeded() {
        guard !AppInstance.wasLaunchedByLaunchd,
            !environment.settings.value(for: Self.hasShownWelcomeKey)
        else { return }

        environment.settings.set(true, for: Self.hasShownWelcomeKey)
        settingsWindow.show()
    }
}
