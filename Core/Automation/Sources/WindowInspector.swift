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

    /// Per-app view of what Accessibility reports, before any filtering.
    ///
    /// Window enumeration fails silently and per app, so a snapshot that comes
    /// back suspiciously empty can only be explained with the raw numbers.
    public func diagnostics() -> [String] {
        let ownProcessID = ProcessInfo.processInfo.processIdentifier

        return NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownProcessID }
            .filter { $0.activationPolicy == .regular }
            .compactMap { application in
                guard let bundleID = application.bundleIdentifier else { return nil }

                let element = AXUIElementCreateApplication(application.processIdentifier)
                AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)

                var raw: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(
                    element,
                    kAXWindowsAttribute as CFString,
                    &raw
                )
                let elements = raw as? [AXUIElement] ?? []
                let subroles = elements.map {
                    AXAttributes.string($0, kAXSubroleAttribute as String) ?? "-"
                }

                return
                    "\(application.localizedName ?? bundleID): статус \(status.rawValue), окон \(elements.count), подроли \(subroles.joined(separator: "/"))"
            }
    }

    /// Windows with the given ids.
    ///
    /// Asking Accessibility about every running app is slow, and most answers are
    /// discarded anyway. The owners of the requested ids come from the public
    /// window list (no Screen Recording needed, since titles are not read there),
    /// so only the apps that matter are queried.
    public func windows(withIDs ids: Set<CGWindowID>) throws -> [LiveWindow] {
        guard AccessibilityAuthorization.isGranted else {
            throw AutomationError.accessibilityDenied
        }

        guard !ids.isEmpty else { return [] }

        let owners = processIDs(owning: ids)

        return NSWorkspace.shared.runningApplications
            .filter { owners.contains($0.processIdentifier) }
            .flatMap(windows(of:))
            .filter { ids.contains($0.id) }
    }

    private func processIDs(owning ids: Set<CGWindowID>) -> Set<pid_t> {
        guard
            let infos = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }

        return Set(
            infos.compactMap { info in
                guard let identifier = info[kCGWindowNumber as String] as? CGWindowID,
                    ids.contains(identifier)
                else { return nil }

                return info[kCGWindowOwnerPID as String] as? pid_t
            }
        )
    }

    /// Whether the app has a normal window on any desktop.
    ///
    /// Uses the public window list rather than Accessibility on purpose:
    /// Accessibility hides windows of desktops that are not visible, so asking it
    /// would report "no windows" for an app that is sitting on another desktop.
    public func hasWindowsAnywhere(bundleID: String) -> Bool {
        let owners = Set(
            NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .map(\.processIdentifier)
        )

        guard !owners.isEmpty else { return false }

        guard
            let infos = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
                as? [[String: Any]]
        else { return false }

        return infos.contains { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t,
                owners.contains(owner)
            else { return false }

            return info[kCGWindowLayer as String] as? Int == 0
        }
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
