import AppKit
import ControlSurface
import Foundation

/// Measures where the system would place Sidekick's menu bar icon.
///
/// Only the one-shot CLI process may do this. The running app already owns a
/// status item, so a second one measures its neighbour, flashes in the bar, and
/// the RunLoop spin it needs would freeze the menu.
@MainActor
enum MenuBarIconProbe {
    /// Fills in the part of a doctor report that only this process can answer.
    static func annotate(_ payload: DoctorPayload) -> DoctorPayload {
        var payload = payload
        if !payload.menuBarIcon.isEmpty {
            return payload
        }

        switch placement() {
        case .visible(let x):
            payload.menuBarIcon = "visible at x=\(Int(x))"
        case .behindNotch(let x, let notch):
            payload.menuBarIcon = "hidden at x=\(Int(x))"
            payload.warnings.append(
                "the menu bar is full, so the icon sits behind the notch "
                    + "(x \(Int(notch.lowerBound))-\(Int(notch.upperBound)))"
            )
        case .unknown:
            payload.menuBarIcon = "could not measure"
        }

        return payload
    }

    private enum IconPlacement {
        case visible(x: CGFloat)
        case behindNotch(x: CGFloat, notch: ClosedRange<CGFloat>)
        case unknown
    }

    /// Places a temporary status item to find out where ours would go.
    private static func placement() -> IconPlacement {
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
}
