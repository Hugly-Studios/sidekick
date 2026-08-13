import AppCore
import AppKit
import SwiftUI

@main
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
        }

        // The menu bar icon can be unreachable (a full menu bar on a notched Mac
        // hides new status items), so the first launch always shows a real window.
        if !environment.settings.value(for: Self.hasShownWelcomeKey) {
            environment.settings.set(true, for: Self.hasShownWelcomeKey)
            settingsWindow.show()
        }
    }

    /// Gives features a real async shutdown hook instead of racing termination.
    func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await environment.features.stop()
            application.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
}
