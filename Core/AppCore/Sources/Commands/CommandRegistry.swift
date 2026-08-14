import OSLog

/// Every command exposed by active features, grouped by owner.
@MainActor
@Observable
public final class CommandRegistry {
    public struct Entry: Identifiable, Sendable {
        public let owner: FeatureID
        public let command: Command

        public var id: CommandID { command.id }
    }

    public private(set) var entries: [Entry] = []

    private let log: Logger

    public init(log: Logger) {
        self.log = log
    }

    public func register(_ commands: [Command], owner: FeatureID) {
        unregister(owner: owner)
        entries.append(contentsOf: commands.map { Entry(owner: owner, command: $0) })
    }

    public func unregister(owner: FeatureID) {
        entries.removeAll { $0.owner == owner }
    }

    public func commands(of owner: FeatureID) -> [Command] {
        entries.filter { $0.owner == owner }.map(\.command)
    }

    public func command(id: CommandID) -> Command? {
        entries.first { $0.command.id == id }?.command
    }

    /// Runs a command and returns its result. Surfaces that cannot await should
    /// call ``runDetached(_:)`` instead.
    @discardableResult
    public func run(_ id: CommandID, argument: String? = nil) async throws -> String {
        guard let command = command(id: id) else {
            throw CommandError.notFound(id)
        }

        return try await command.run(argument)
    }

    /// Fire-and-forget entry used by the menu bar. Failures are logged here.
    public func runDetached(_ id: CommandID) {
        Task {
            do {
                _ = try await run(id)
            } catch {
                log.error(
                    "Command \(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}

public enum CommandError: Error, LocalizedError {
    case notFound(CommandID)

    nonisolated public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            "Команда не найдена: \(id.rawValue)"
        }
    }
}
