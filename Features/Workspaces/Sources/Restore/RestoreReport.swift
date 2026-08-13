import Foundation

public enum RestoreMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Restore what the snapshot describes, leave everything else alone.
    case additive
    /// Additionally quit apps that the snapshot does not mention.
    case strict

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .additive: "Только восстановить"
        case .strict: "Строгий: закрыть лишние приложения"
        }
    }
}

/// Outcome of a restore. Best-effort by design: a single stubborn app must not
/// abort the whole layout, so problems are collected instead of thrown.
public struct RestoreReport: Sendable, Equatable {
    public var launchedApps: Int = 0
    public var movedWindows: Int = 0
    public var arrangedWindows: Int = 0
    public var quitApps: Int = 0
    public var problems: [String] = []
    public var finishedAt: Date = Date()

    public var isClean: Bool { problems.isEmpty }

    public var summary: String {
        let parts = [
            "приложений запущено: \(launchedApps)",
            "окон перенесено: \(movedWindows)",
            "окон расставлено: \(arrangedWindows)",
            quitApps > 0 ? "закрыто: \(quitApps)" : nil,
        ].compactMap(\.self)

        return parts.joined(separator: ", ")
    }

    mutating func merge(_ other: RestoreReport) {
        launchedApps += other.launchedApps
        movedWindows += other.movedWindows
        arrangedWindows += other.arrangedWindows
        quitApps += other.quitApps
        problems.append(contentsOf: other.problems)
    }
}
