import Foundation

/// Snapshots on disk, one JSON file each.
///
/// Plain files rather than `UserDefaults`: a layout is large, worth reading by
/// hand when something goes wrong, and easy to back up or copy between machines.
public struct SnapshotStore: Sendable {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory =
            directory
            ?? URL.applicationSupportDirectory
            .appending(path: "Sidekick/Workspaces", directoryHint: .isDirectory)
    }

    public func all() -> [WorkspaceSnapshot] {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return
            files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(WorkspaceSnapshot.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func snapshot(id: UUID) -> WorkspaceSnapshot? {
        all().first { $0.id == id }
    }

    public func save(_ snapshot: WorkspaceSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        try encoder.encode(snapshot).write(to: url(for: snapshot.id), options: .atomic)
    }

    public func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }

    private func url(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
