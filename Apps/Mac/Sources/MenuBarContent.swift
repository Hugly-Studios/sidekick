import AppCore
import SwiftUI

/// Menu bar dropdown assembled from the feature and command registries.
///
/// Feature menu content must be menu-compatible (`Button`, `Toggle`, `Text`,
/// `Divider`) because the extra uses the native `.menu` style.
struct MenuBarContent: View {
    let environment: AppEnvironment
    let settingsWindow: SettingsWindowController

    private var activeEntries: [FeatureRegistry.Entry] {
        environment.features.entries.filter { $0.isEnabled && $0.failure == nil }
    }

    var body: some View {
        if activeEntries.isEmpty {
            Text("Нет включённых модулей")
        }

        ForEach(activeEntries) { entry in
            Section(entry.descriptor.title) {
                if let menuView = entry.feature.makeMenuView() {
                    menuView
                }

                ForEach(environment.commands.commands(of: entry.id)) { command in
                    Button(command.title) {
                        environment.commands.runDetached(command.id)
                    }
                }
            }
        }

        Divider()

        Button("Настройки…") {
            settingsWindow.show()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Выйти") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
