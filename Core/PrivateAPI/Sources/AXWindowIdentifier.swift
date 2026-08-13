import ApplicationServices
import CoreGraphics

/// Bridges an Accessibility window to its `CGWindowID`.
///
/// The public AX API never exposes the window id, and the alternative —
/// matching AX windows against `CGWindowListCopyWindowInfo` by title — needs
/// Screen Recording permission and breaks on windows with equal titles.
/// `_AXUIElementGetWindow` is private but exported, so it resolves at link time.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: inout CGWindowID)
    -> AXError

public enum AXWindowIdentifier {
    public static func of(_ element: AXUIElement) -> CGWindowID? {
        var identifier: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &identifier) == .success, identifier != 0 else {
            return nil
        }

        return identifier
    }
}
