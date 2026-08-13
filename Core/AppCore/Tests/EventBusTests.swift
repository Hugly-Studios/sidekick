import Testing

@testable import AppCore

private struct CodeReceived: AppEvent, Equatable {
    let code: String
}

private struct SnapshotRestored: AppEvent, Equatable {
    let name: String
}

struct EventBusTests {
    @Test func deliversEventsToSubscribersOfThatType() async throws {
        let bus = EventBus()
        var codes = await bus.stream(of: CodeReceived.self).makeAsyncIterator()

        await bus.publish(CodeReceived(code: "1234"))

        #expect(await codes.next() == CodeReceived(code: "1234"))
    }

    @Test func doesNotDeliverEventsOfOtherTypes() async throws {
        let bus = EventBus()
        var snapshots = await bus.stream(of: SnapshotRestored.self).makeAsyncIterator()

        await bus.publish(CodeReceived(code: "1234"))
        await bus.publish(SnapshotRestored(name: "work"))

        // The unrelated event must not appear in this stream.
        #expect(await snapshots.next() == SnapshotRestored(name: "work"))
    }

    @Test func publishingWithoutSubscribersIsSafe() async {
        let bus = EventBus()

        await bus.publish(CodeReceived(code: "0000"))
    }
}
