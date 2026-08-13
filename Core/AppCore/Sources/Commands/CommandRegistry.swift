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

    /// Runs a command and logs failures — surfaces must not swallow them silently.
    public func run(_ id: CommandID) {
        guard let command = command(id: id) else {
            log.error("Command not found: \(id.rawValue, privacy: .public)")
            return
        }

        Task {
            do {
                try await command.run()
            } catch {
                log.error(
                    "Command \(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
