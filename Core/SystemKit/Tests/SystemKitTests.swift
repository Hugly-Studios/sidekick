import Foundation
import Testing

@testable import SystemKit

struct SystemKitTests {
    @Test func systemClockReportsASaneDate() {
        let clock = SystemClock()
        let interval = clock.now.timeIntervalSince1970

        #expect(interval > 1_000_000_000)
    }

    @Test func livePowerStateAnswersWithoutCrashing() {
        let power = LivePowerState()

        _ = power.batteryLevel
        _ = power.isOnACPower
        _ = power.thermalState
    }

    @Test func workspaceObserverSeesThisProcess() {
        let observer = LiveWorkspaceObserver()
        let ids = observer.runningBundleIDs

        #expect(!ids.isEmpty)
    }
}
