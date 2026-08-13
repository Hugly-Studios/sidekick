import Foundation
import OSLog

public enum AppLog {
    public static let subsystem = Bundle.main.bundleIdentifier ?? "com.hugly.sidekick"

    public static func make(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
