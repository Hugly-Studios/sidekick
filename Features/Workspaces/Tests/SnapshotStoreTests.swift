import Foundation
import Testing

@testable import Workspaces

private func makeSnapshot(
    name: String,
    createdAt: Date = Date(),
    spaces: Int = 1,
    windowsPerSpace: Int = 1
) -> WorkspaceSnapshot {
    let window = WindowSnapshot(
        bundleID: "com.apple.TextEdit",
        appName: "TextEdit",
        title: "Заметки",
        frame: FrameSnapshot(x: 10, y: 20, width: 300, height: 400),
        isMinimized: false,
        isFullscreen: false
    )

    return WorkspaceSnapshot(
        name: name,
        createdAt: createdAt,
        displays: [
            DisplaySnapshot(
                uuid: "Main",
                spaces: (1...spaces).map { index in
                    SpaceSnapshot(
                        index: index,
                        uuid: "space-\(index)",
                        kind: .user,
                        isActive: index == 1,
                        windows: Array(repeating: window, count: windowsPerSpace)
                    )
                }
            )
        ]
    )
}

struct SnapshotStoreTests {
    private func makeStore() -> SnapshotStore {
        let directory = URL.temporaryDirectory.appending(path: "sidekick-tests/\(UUID())")
        return SnapshotStore(directory: directory)
    }

    @Test func roundTripsASnapshot() throws {
        let store = makeStore()
        let snapshot = makeSnapshot(name: "работа", spaces: 2, windowsPerSpace: 3)

        try store.save(snapshot)

        #expect(store.snapshot(id: snapshot.id) == snapshot)
    }

    @Test func listsNewestFirst() throws {
        let store = makeStore()
        let older = makeSnapshot(name: "старый", createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeSnapshot(name: "новый", createdAt: Date(timeIntervalSince1970: 2_000))

        try store.save(older)
        try store.save(newer)

        #expect(store.all().map(\.name) == ["новый", "старый"])
    }

    @Test func deletesASnapshot() throws {
        let store = makeStore()
        let snapshot = makeSnapshot(name: "временный")
        try store.save(snapshot)

        try store.delete(id: snapshot.id)

        #expect(store.all().isEmpty)
    }

    @Test func returnsNothingForAMissingDirectory() {
        #expect(makeStore().all().isEmpty)
    }
}

struct WorkspaceSnapshotTests {
    @Test func countsSpacesAndWindows() {
        let snapshot = makeSnapshot(name: "тест", spaces: 3, windowsPerSpace: 2)

        #expect(snapshot.spaceCount == 3)
        #expect(snapshot.windowCount == 6)
    }

    @Test func exposesSpaceOrderForDriftDetection() {
        let snapshot = makeSnapshot(name: "тест", spaces: 3)

        #expect(snapshot.spaceOrder == ["space-1", "space-2", "space-3"])
    }
}
