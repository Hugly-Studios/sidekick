import Foundation
import Testing

@testable import Sounds

struct OutputHistoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func shortSoundStaysInRecent() {
        var history = OutputHistory()
        history.started(bundleID: "com.apple.Safari", pid: 10, deviceName: "Динамики", at: t0)
        history.stopped(bundleID: "com.apple.Safari", pid: 10, at: t0)

        #expect(history.current(hidingSystem: false).isEmpty)

        let recent = history.recent(since: t0.addingTimeInterval(-60), hidingSystem: false)
        #expect(recent.count == 1)
        #expect(recent[0].bundleID == "com.apple.Safari")
        #expect(recent[0].relativeDescription(now: t0.addingTimeInterval(12)) == "играл 12 с назад")
    }

    @Test func debounceKeepsOriginalStart() {
        var history = OutputHistory()
        history.started(bundleID: "com.apple.Music", pid: 1, deviceName: "Динамики", at: t0)
        history.started(
            bundleID: "com.apple.Music",
            pid: 2,
            deviceName: "Наушники",
            at: t0.addingTimeInterval(1)
        )

        let current = history.current(hidingSystem: false)
        #expect(current.count == 1)
        #expect(current[0].startedAt == t0)
        #expect(current[0].pid == 2)
        #expect(current[0].deviceName == "Наушники")
    }

    @Test func systemProcessIsLabeledAndNotMuteable() {
        var history = OutputHistory()
        history.started(bundleID: "", pid: 3, deviceName: "Динамики", at: t0)

        let current = history.current(hidingSystem: false)
        #expect(current[0].isSystem)
        #expect(!SystemAudioIdentity.allowsMute(current[0].bundleID))
        #expect(history.current(hidingSystem: true).isEmpty)
    }

    @Test func systemSoundServerIsSystem() {
        #expect(SystemAudioIdentity.isSystem(bundleID: "systemsoundserverd"))
        #expect(!SystemAudioIdentity.allowsMute("systemsoundserverd"))
    }

    @Test func latestNonSystemSkipsCoreAudio() {
        var history = OutputHistory()
        history.started(
            bundleID: "com.apple.audio.coreaudiod",
            pid: 4,
            deviceName: "Динамики",
            at: t0
        )
        history.started(bundleID: "com.apple.Safari", pid: 5, deviceName: "Динамики", at: t0)

        #expect(history.latestNonSystem()?.bundleID == "com.apple.Safari")
    }
}
