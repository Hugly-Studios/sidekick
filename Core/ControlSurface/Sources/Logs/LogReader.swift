import Foundation
import OSLog

public enum LogReader {
    public static func fetch(
        subsystem: String = "com.hugly.sidekick",
        since seconds: Double,
        level: String? = nil
    ) throws -> [LogRecord] {
        let store = try OSLogStore.local()
        let start = store.position(date: Date().addingTimeInterval(-seconds))
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        let entries = try store.getEntries(at: start, matching: predicate)

        return entries.compactMap { entry in
            guard let log = entry as? OSLogEntryLog else { return nil }

            let record = LogRecord(
                date: log.date,
                category: log.category,
                level: levelName(log.level),
                message: log.composedMessage
            )

            if let level, record.level != level {
                return nil
            }

            return record
        }
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: "undefined"
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        @unknown default: "unknown"
        }
    }
}
