import AppKit
import Foundation

/// Names and lifecycle of running apps without AppKit in a feature.
public protocol RunningApplications: Sendable {
    func localizedName(for bundleID: String) -> String?
    func activate(bundleID: String)
    func terminate(bundleID: String) -> Bool
    func open(url: URL)
}

public struct LiveRunningApplications: RunningApplications {
    public init() {}

    public func localizedName(for bundleID: String) -> String? {
        if let name = running(bundleID)?.localizedName, !name.isEmpty {
            return name
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
            let bundle = Bundle(url: url)
        else { return nil }

        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
    }

    public func activate(bundleID: String) {
        running(bundleID)?.activate()
    }

    public func terminate(bundleID: String) -> Bool {
        running(bundleID)?.terminate() ?? false
    }

    public func open(url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func running(_ bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }
}
