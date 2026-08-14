import Foundation

/// One request from the CLI process to the running app.
public struct ControlRequest: Codable, Sendable, Identifiable {
    public let id: UUID
    public let operation: Operation

    public init(id: UUID = UUID(), operation: Operation) {
        self.id = id
        self.operation = operation
    }

    public enum Operation: Codable, Sendable, Equatable {
        case status
        case featuresList
        case featureEnable(id: String)
        case featureDisable(id: String)
        case commands
        case run(id: String, argument: String?)
        case settingsGet(key: String)
        case settingsSet(key: String, value: String)
        case logs(sinceSeconds: Double, level: String?)
        case doctor
        case quit
    }
}
