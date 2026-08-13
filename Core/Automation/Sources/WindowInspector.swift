import AppKit
import ApplicationServices
import CoreGraphics
import PrivateAPI

/// Reads the windows that are open right now.
@MainActor
public struct WindowInspector {
    public init() {}

    /// Standard windows of every visible app, excluding Sidekick itself.
    public func windows() throws -> [LiveWindow] {
        guard AccessibilityAuthorization.isGranted else {
            throw AutomationError.accessibilityDenied
        }

        let ownProcessID = ProcessInfo.processInfo.processIdentifier

        return NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownProcessID }
            .filter { $0.activationPolicy != .prohibited }
            .flatMap(windows(of:))
    }

    public func windows(ofBundleID bundleID: String) -> [LiveWindow] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleID }
            .flatMap(windows(of:))
    }

    private func windows(of application: NSRunningApplication) -> [LiveWindow] {
        guard let bundleID = application.bundleIdentifier else { return [] }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        // An unresponsive app must not stall a whole snapshot.
        AXUIElementSetMessagingTimeout(applicationElement, Self.messagingTimeout)

        guard
            let elements: [AXUIElement] = AXAttributes.value(
                applicationElement,
                kAXWindowsAttribute as String
            )
        else { return [] }

        return elements.compactMap { element in
            window(
                element: element,
                bundleID: bundleID,
                appName: application.localizedName ?? bundleID,
                processID: application.processIdentifier
            )
        }
    }

    private func window(
        element: AXUIElement,
        bundleID: String,
        appName: String,
        processID: pid_t
    ) -> LiveWindow? {
        // Palettes, sheets and dialogs are not part of a workspace layout.
        guard
            AXAttributes.string(element, kAXSubroleAttribute as String) == kAXStandardWindowSubrole
        else { return nil }

        guard let windowID = AXWindowIdentifier.of(element),
            let position = AXAttributes.point(element, kAXPositionAttribute as String),
            let size = AXAttributes.size(element, kAXSizeAttribute as String)
        else { return nil }

        return LiveWindow(
            id: windowID,
            processID: processID,
            bundleID: bundleID,
            appName: appName,
            title: AXAttributes.string(element, kAXTitleAttribute as String) ?? "",
            frame: CGRect(origin: position, size: size),
            isMinimized: AXAttributes.bool(element, kAXMinimizedAttribute as String) ?? false,
            isFullscreen: AXAttributes.bool(element, AXAttributes.fullScreen) ?? false,
            element: element
        )
    }

    private static let messagingTimeout: Float = 1
}
