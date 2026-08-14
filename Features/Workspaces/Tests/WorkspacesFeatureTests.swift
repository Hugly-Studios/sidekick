import AppCore
import Automation
import Foundation
import TestSupport
import Testing

@testable import Workspaces

@MainActor
struct WorkspacesFeatureTests {
    @Test func constructsWithInjectedStore() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "sidekick-ws-\(UUID().uuidString)", directoryHint: .isDirectory)
        let feature = WorkspacesFeature(
            context: TestFeatureContext.make(id: "workspaces"),
            store: SnapshotStore(directory: directory),
            spaces: nil,
            navigator: nil,
            inspector: WindowInspector()
        )

        #expect(type(of: feature).descriptor.id.rawValue == "workspaces")
        #expect(feature.snapshots.isEmpty)
    }
}
