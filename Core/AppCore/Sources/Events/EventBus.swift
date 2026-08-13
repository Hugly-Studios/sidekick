import Foundation

/// Marker for anything published on the ``EventBus``.
public protocol AppEvent: Sendable {}

/// Typed broadcast channel that lets features react to each other without
/// depending on each other.
public actor EventBus {
    private typealias Delivery = @Sendable (any AppEvent) -> Void

    private var subscribers: [ObjectIdentifier: [UUID: Delivery]] = [:]

    public init() {}

    public func publish<Event: AppEvent>(_ event: Event) {
        for delivery in subscribers[ObjectIdentifier(Event.self), default: [:]].values {
            delivery(event)
        }
    }

    public func stream<Event: AppEvent>(of type: Event.Type) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let subscriptionID = UUID()
            let typeKey = ObjectIdentifier(type)

            subscribers[typeKey, default: [:]][subscriptionID] = { event in
                guard let typed = event as? Event else { return }
                continuation.yield(typed)
            }

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(subscriptionID, typeKey: typeKey) }
            }
        }
    }

    private func removeSubscriber(_ subscriptionID: UUID, typeKey: ObjectIdentifier) {
        subscribers[typeKey]?.removeValue(forKey: subscriptionID)

        if subscribers[typeKey]?.isEmpty == true {
            subscribers.removeValue(forKey: typeKey)
        }
    }
}
