import AppCore
import Foundation

/// Thin wrapper so tests can publish and subscribe without extra ceremony.
public enum RecordingEventBus {
    public static func make() -> EventBus {
        EventBus()
    }
}
