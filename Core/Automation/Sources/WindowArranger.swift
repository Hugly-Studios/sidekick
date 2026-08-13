import ApplicationServices
import CoreGraphics

/// Moves, resizes and (un)minimizes existing windows.
@MainActor
public struct WindowArranger {
    public init() {}

    /// Applies a frame.
    ///
    /// Position is set twice on purpose: many apps clamp the size to the space
    /// they currently sit on, so the first move gets the window onto the right
    /// screen area and the second one lands it exactly.
    public func setFrame(_ frame: CGRect, of window: LiveWindow) throws {
        _ = AXAttributes.setPoint(frame.origin, window.element, kAXPositionAttribute as String)

        guard AXAttributes.setSize(frame.size, window.element, kAXSizeAttribute as String) else {
            throw AutomationError.attributeNotWritable("размер")
        }

        _ = AXAttributes.setPoint(frame.origin, window.element, kAXPositionAttribute as String)
    }

    public func setMinimized(_ isMinimized: Bool, of window: LiveWindow) throws {
        guard
            AXAttributes.setBool(isMinimized, window.element, kAXMinimizedAttribute as String)
        else {
            throw AutomationError.attributeNotWritable("свёрнутое состояние")
        }
    }

    public func setFullscreen(_ isFullscreen: Bool, of window: LiveWindow) throws {
        guard AXAttributes.setBool(isFullscreen, window.element, AXAttributes.fullScreen) else {
            throw AutomationError.attributeNotWritable("полноэкранный режим")
        }
    }
}
