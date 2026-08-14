import Foundation

/// Time and sleeping, so features can be tested without waiting on the wall clock.
public protocol Clock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

public struct SystemClock: Clock {
    public init() {}

    public var now: Date { Date() }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
