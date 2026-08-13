import ApplicationServices
import CoreGraphics

/// Thin typed wrappers over the Accessibility attribute API.
enum AXAttributes {
    /// A window that is fullscreen or tiled by the system.
    static let fullScreen = "AXFullScreen"

    static func value<Value>(_ element: AXUIElement, _ attribute: String) -> Value? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }

        return raw as? Value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute)
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        value(element, attribute)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let axValue: AXValue = value(element, attribute) else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }

        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let axValue: AXValue = value(element, attribute) else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }

        return size
    }

    static func setPoint(_ point: CGPoint, _ element: AXUIElement, _ attribute: String) -> Bool {
        var point = point
        guard let axValue = AXValueCreate(.cgPoint, &point) else { return false }

        return AXUIElementSetAttributeValue(element, attribute as CFString, axValue) == .success
    }

    static func setSize(_ size: CGSize, _ element: AXUIElement, _ attribute: String) -> Bool {
        var size = size
        guard let axValue = AXValueCreate(.cgSize, &size) else { return false }

        return AXUIElementSetAttributeValue(element, attribute as CFString, axValue) == .success
    }

    static func setBool(_ flag: Bool, _ element: AXUIElement, _ attribute: String) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, flag as CFBoolean) == .success
    }
}
