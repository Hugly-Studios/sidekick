import Foundation

enum SystemAudioIdentity {
    static let bundleIDs: Set<String> = [
        "com.apple.audio.coreaudiod",
        "com.apple.controlcenter",
        "com.apple.ControlCenter",
        "com.apple.systempreferences",
        "com.apple.Settings",
        "com.apple.loginwindow",
        "com.apple.audio.AudioComponentRegistrar",
        "systemsoundserverd",
        "com.apple.PowerChime",
        "com.apple.CoreSpeech",
        "com.apple.mediaremoted",
        "com.apple.audiomxd",
    ]

    static let quitDenied: Set<String> = [
        "com.apple.finder",
        "com.hugly.sidekick",
        "com.apple.loginwindow",
    ]

    static func isSystem(bundleID: String) -> Bool {
        if bundleID.isEmpty { return true }
        if bundleIDs.contains(bundleID) { return true }
        return bundleID.hasPrefix("com.apple.audio.")
    }

    static func allowsMute(_ bundleID: String) -> Bool {
        !isSystem(bundleID: bundleID)
    }

    static func allowsQuit(_ bundleID: String) -> Bool {
        !bundleID.isEmpty && !isSystem(bundleID: bundleID) && !quitDenied.contains(bundleID)
    }
}
