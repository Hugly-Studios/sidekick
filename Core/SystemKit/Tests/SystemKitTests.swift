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

    @Test func runningApplicationsResolvesFinder() {
        let apps = LiveRunningApplications()

        #expect(apps.localizedName(for: "com.apple.finder") != nil)
    }

    @Test func audioOutputSnapshotDoesNotCrash() {
        let observer = LiveAudioOutputObserver()

        _ = observer.snapshot()
    }

    @Test func outputTransitionRecordsAMissedShortPulse() {
        let kinds = AudioOutputTransition.events(
            previousRunning: false,
            currentRunning: false,
            allowPulse: true
        )

        #expect(kinds == [.started, .stopped])
    }

    @Test func outputTransitionIgnoresPulseBeforeListenerIsArmed() {
        let kinds = AudioOutputTransition.events(
            previousRunning: false,
            currentRunning: false,
            allowPulse: false
        )

        #expect(kinds.isEmpty)
    }

    @Test func outputTransitionStartsAndStopsNormally() {
        #expect(
            AudioOutputTransition.events(
                previousRunning: false,
                currentRunning: true,
                allowPulse: false
            ) == [.started]
        )
        #expect(
            AudioOutputTransition.events(
                previousRunning: true,
                currentRunning: false,
                allowPulse: true
            ) == [.stopped]
        )
    }
}
