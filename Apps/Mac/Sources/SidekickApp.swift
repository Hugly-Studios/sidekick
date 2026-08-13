import AppKit
import SwiftUI

@main
struct SidekickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Sidekick", systemImage: "square.grid.2x2") {
            MenuBarContent(environment: appDelegate.environment)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView(environment: appDelegate.environment)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let environment = AppEnvironment()

    func applicationDidFinishLaunching(_: Notification) {
        Task { @MainActor in
            await environment.features.start()
        }
    }

    /// Gives features a real async shutdown hook instead of racing termination.
    func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await environment.features.stop()
            application.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
}
