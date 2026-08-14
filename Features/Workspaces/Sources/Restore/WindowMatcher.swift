import CoreGraphics

/// A window that exists now and could correspond to a snapshot entry.
public struct MatchCandidate: Sendable, Equatable, Identifiable {
    public let id: CGWindowID
    public let bundleID: String
    public let title: String

    public init(id: CGWindowID, bundleID: String, title: String) {
        self.id = id
        self.bundleID = bundleID
        self.title = title
    }
}

/// Decides which live window corresponds to which saved window.
///
/// Window ids are recreated on every launch, so a snapshot can only be matched by
/// app plus title, and titles change (documents get renamed, tabs move). Hence
/// three passes with decreasing confidence, never reusing a candidate twice.
public enum WindowMatcher {
    /// Maps snapshot positions to candidate window ids.
    public static func pair(
        snapshots: [WindowSnapshot],
        candidates: [MatchCandidate]
    ) -> [Int: CGWindowID] {
        var available = Dictionary(grouping: candidates, by: \.bundleID)
        var pairs: [Int: CGWindowID] = [:]

        for pass in Pass.allCases {
            for (index, snapshot) in snapshots.enumerated() where pairs[index] == nil {
                guard var group = available[snapshot.bundleID], !group.isEmpty else { continue }
                guard let position = pass.position(of: snapshot, in: group) else { continue }

                pairs[index] = group[position].id
                group.remove(at: position)
                available[snapshot.bundleID] = group
            }
        }

        return pairs
    }

    private enum Pass: CaseIterable {
        case exactTitle
        case partialTitle
        case order

        func position(of snapshot: WindowSnapshot, in candidates: [MatchCandidate]) -> Int? {
            switch self {
            case .exactTitle:
                guard !snapshot.title.isEmpty else { return nil }
                return candidates.firstIndex { $0.title == snapshot.title }
            case .partialTitle:
                guard snapshot.title.count >= Self.minimumPartialLength else { return nil }
                return candidates.firstIndex {
                    $0.title.contains(snapshot.title)
                        || snapshot.title.contains($0.title)
                            && !$0.title.isEmpty
                }
            case .order:
                return candidates.isEmpty ? nil : 0
            }
        }

        /// Short titles like "1" would match almost anything.
        private static let minimumPartialLength = 4
    }
}
