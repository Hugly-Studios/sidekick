import AppKit
import Foundation

public protocol Pasteboarding: Sendable {
    var string: String? { get set }
}

public struct LivePasteboard: Pasteboarding {
    public init() {}

    public var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        nonmutating set {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let newValue {
                pasteboard.setString(newValue, forType: .string)
            }
        }
    }
}
