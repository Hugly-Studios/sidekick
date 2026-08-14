import Foundation
import IOKit.ps

/// Battery, AC power and thermal state — shared by Awake, Presence and Habits.
public protocol PowerState: Sendable {
    var batteryLevel: Double? { get }
    var isOnACPower: Bool { get }
    var thermalState: ProcessInfo.ThermalState { get }
}

public struct LivePowerState: PowerState {
    public init() {}

    public var batteryLevel: Double? {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Double,
                let max = description[kIOPSMaxCapacityKey] as? Double,
                max > 0
            else { continue }

            return current / max
        }

        return nil
    }

    public var isOnACPower: Bool {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return true }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                let state = description[kIOPSPowerSourceStateKey] as? String
            else { continue }

            return state == kIOPSACPowerValue
        }

        return true
    }

    public var thermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }
}
