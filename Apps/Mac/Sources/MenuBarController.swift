import AppKit
import SwiftUI

/// Owns the menu bar item so it cannot be dragged out and stays on the visible
/// side of the notch instead of disappearing into overflow.
@MainActor
final class MenuBarController {
    private static let autosaveName = "Sidekick"
    private let item: NSStatusItem
    private var observers: [NSObjectProtocol] = []

    init(environment: AppEnvironment, settingsWindow: SettingsWindowController) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "NSStatusItem Visible \(Self.autosaveName)")
        // Small value = trailing edge (near Control Center). Large values sit
        // toward the notch and macOS hides them when the bar is full.
        defaults.set(1, forKey: "NSStatusItem Preferred Position \(Self.autosaveName)")

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = NSStatusItem.AutosaveName(Self.autosaveName)
        item.behavior = []
        item.isVisible = true
        item.button?.image = NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: "Sidekick"
        )
        item.button?.image?.isTemplate = true
        item.menu = NSHostingMenu(
            rootView: MenuBarContent(
                environment: environment,
                settingsWindow: settingsWindow
            )
        )
        self.item = item
        observeReappearance()
    }

    func iconReport() -> (icon: String, warning: String?) {
        guard let frame = item.button?.window?.frame, frame.width > 0 else {
            return ("could not measure", nil)
        }

        guard let screen = NSScreen.main,
            let leftArea = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        else {
            return ("visible at x=\(Int(frame.minX))", nil)
        }

        let notch = leftArea.maxX...rightArea.minX
        if notch.contains(frame.midX) {
            return (
                "hidden at x=\(Int(frame.minX))",
                "the menu bar is full, so the icon sits behind the notch "
                    + "(x \(Int(notch.lowerBound))-\(Int(notch.upperBound)))"
            )
        }

        return ("visible at x=\(Int(frame.minX))", nil)
    }

    private func observeReappearance() {
        let names: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]

        for name in names {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.item.isVisible = true
                }
            }
            observers.append(observer)
        }
    }
}
