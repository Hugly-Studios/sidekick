import Foundation
import SystemKit

/// A clock the test advances by hand.
public final class FakeClock: Clock, @unchecked Sendable {
    public var now: Date
    private var continuations: [UUID: CheckedContinuation<Void, Error>] = [:]

    public init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = now
    }

    public func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation
        }
    }

    public func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting.values {
            continuation.resume()
        }
    }
}
