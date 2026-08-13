import ApplicationServices
import CoreGraphics

/// A window that exists right now, with the handle needed to move it.
///
/// Not `Sendable` on purpose: `AXUIElement` is only valid while its app lives and
/// all access is kept on the main actor.
public struct LiveWindow: Identifiable {
    public let id: CGWindowID
    public let processID: pid_t
    public let bundleID: String
    public let appName: String
    public let title: String
    public let frame: CGRect
    public let isMinimized: Bool
    public let isFullscreen: Bool

    let element: AXUIElement

    init(
        id: CGWindowID,
        processID: pid_t,
        bundleID: String,
        appName: String,
        title: String,
        frame: CGRect,
        isMinimized: Bool,
        isFullscreen: Bool,
        element: AXUIElement
    ) {
        self.id = id
        self.processID = processID
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.element = element
    }
}

public enum AutomationError: Error, LocalizedError, Equatable {
    case accessibilityDenied
    case applicationNotFound(bundleID: String)
    case applicationDidNotOpenWindows(bundleID: String)
    case attributeNotWritable(String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            "Нет доступа к управлению компьютером (Универсальный доступ)"
        case .applicationNotFound(let bundleID):
            "Приложение \(bundleID) не установлено"
        case .applicationDidNotOpenWindows(let bundleID):
            "Приложение \(bundleID) запустилось, но не открыло окон"
        case .attributeNotWritable(let attribute):
            "Окно не позволяет изменить \(attribute)"
        }
    }
}
