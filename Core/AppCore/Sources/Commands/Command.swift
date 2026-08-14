/// Stable identifier of a command, e.g. `"awake.toggle"`.
public struct CommandID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

/// A single action a feature exposes.
///
/// Declared once, then rendered by every surface: menu bar item, global hotkey,
/// and the CLI.
public struct Command: Identifiable, Sendable {
    public let id: CommandID
    public let title: String
    public let symbolName: String?
    public let run: @MainActor @Sendable (_ argument: String?) async throws -> String

    public init(
        id: CommandID,
        title: String,
        symbolName: String? = nil,
        run: @escaping @MainActor @Sendable () async throws -> Void
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.run = { _ in
            try await run()
            return ""
        }
    }

    public init(
        id: CommandID,
        title: String,
        symbolName: String? = nil,
        run: @escaping @MainActor @Sendable (String?) async throws -> String
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.run = run
    }
}
