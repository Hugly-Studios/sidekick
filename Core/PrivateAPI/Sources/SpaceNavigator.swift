import CoreGraphics
import Foundation

public protocol SpaceNavigating: Sendable {
    /// Switches the display to a desktop and returns once the system confirms it.
    func activate(spaceID: SpaceID, displayUUID: String) async throws
}

/// Switches desktops by synthesizing the gesture the trackpad sends.
///
/// macOS exposes no API for activating a Space. The documented-looking private
/// calls only pretend to switch (windows become manipulable while the screen
/// stays put), and yabai's approach to a real switch is a high-velocity dock
/// swipe event, which also skips the animation. Attribution:
/// https://github.com/koekeishiya/yabai (space_manager_focus_space_using_gesture)
///
/// Needed because Accessibility only exposes windows of the visible desktop, so
/// reading or arranging any other desktop means going there first.
public struct SkyLightSpaceNavigator: SpaceNavigating {
    private let bridge: SkyLightBridge
    private let spaces: SkyLightSpaces

    public init?() {
        guard let bridge = SkyLightBridge.shared, let spaces = SkyLightSpaces() else { return nil }
        self.bridge = bridge
        self.spaces = spaces
    }

    public func activate(spaceID: SpaceID, displayUUID: String) async throws {
        guard let display = spaces.displays().first(where: { $0.displayUUID == displayUUID }),
            let target = display.spaces.firstIndex(where: { $0.id == spaceID })
        else {
            throw PrivateAPIError.spaceNotFound(spaceID)
        }

        guard let current = display.spaces.firstIndex(where: { $0.id == display.currentSpaceID })
        else {
            throw PrivateAPIError.spaceNotFound(display.currentSpaceID)
        }

        guard target != current else { return }

        swipe(steps: target - current)

        guard try await waitUntilActive(spaceID: spaceID, displayUUID: displayUUID) else {
            throw PrivateAPIError.spaceSwitchFailed(spaceID)
        }
    }

    private func waitUntilActive(spaceID: SpaceID, displayUUID: String) async throws -> Bool {
        let deadline = ContinuousClock.now + Self.switchTimeout

        while ContinuousClock.now < deadline {
            if bridge.currentSpaceID(displayUUID: displayUUID) == spaceID {
                // The window list of the new desktop appears a moment after the switch.
                try await Task.sleep(for: Self.settleDelay)
                return true
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        return false
    }

    /// One begin/end pair per desktop, in the direction of travel.
    private func swipe(steps: Int) {
        guard let event = CGEvent(source: nil) else { return }

        let direction: Double = steps > 0 ? 1 : -1

        set(event, .eventType, 30)
        set(event, .gestureHIDType, 23)
        set(event, .gestureMotion, 1)
        setDouble(event, .gestureProgress, direction)
        setDouble(event, .gestureVelocityX, direction * 9999)

        for _ in 0..<abs(steps) {
            set(event, .gesturePhase, 1)
            event.post(tap: .cgSessionEventTap)
            set(event, .gesturePhase, 4)
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func set(_ event: CGEvent, _ field: GestureField, _ value: Int64) {
        guard let field = CGEventField(rawValue: field.rawValue) else { return }
        event.setIntegerValueField(field, value: value)
    }

    private func setDouble(_ event: CGEvent, _ field: GestureField, _ value: Double) {
        guard let field = CGEventField(rawValue: field.rawValue) else { return }
        event.setDoubleValueField(field, value: value)
    }

    /// Undocumented CGEvent fields describing a dock swipe.
    private enum GestureField: UInt32 {
        case eventType = 55
        case gestureHIDType = 110
        case gestureMotion = 123
        case gestureProgress = 124
        case gestureVelocityX = 129
        case gesturePhase = 132
    }

    private static let switchTimeout = Duration.seconds(3)
    private static let settleDelay = Duration.milliseconds(350)
}
