import AppCore
import CoreAudio
import Foundation
import SystemKit
import TestSupport
import Testing

@testable import Sounds

@MainActor
struct SoundsFeatureTests {
    @Test func constructsWithInjectedDependencies() {
        let env = Environment()
        #expect(type(of: env.feature).descriptor.id.rawValue == "sounds")
        #expect(type(of: env.feature).descriptor.isEnabledByDefault == false)
    }

    @Test func statusReconcilesFromSnapshotWithoutEvents() async throws {
        let env = Environment()
        try await env.feature.activate()
        env.audio.seed(
            AudioOutputProcess(
                objectID: 12,
                pid: 12,
                bundleID: "com.apple.Safari",
                deviceName: "Динамики",
                isRunningOutput: true
            )
        )

        let status = try? await env.feature.commands.first { $0.id.rawValue == "sounds.status" }?
            .run(nil)
        #expect(status?.contains("сейчас") == true)
        #expect(status?.contains("Safari") == true)
    }

    @Test func statusListsCurrentAndRecent() async throws {
        let env = Environment()
        try await env.feature.activate()
        env.audio.emit(started("com.apple.Safari", pid: 11, at: env.clock.now))
        await env.waitUntil { !env.feature.current.isEmpty }
        env.audio.emit(stopped("com.apple.Safari", pid: 11, at: env.clock.now))
        await env.waitUntil { env.feature.current.isEmpty && !env.feature.recent.isEmpty }

        let status = try? await env.feature.commands.first { $0.id.rawValue == "sounds.status" }?
            .run(nil)
        #expect(status?.contains("недавно") == true)
        #expect(status?.contains("Safari") == true)
    }

    @Test func muteWithoutArgumentUsesLatestNonSystem() async throws {
        let env = Environment()
        try await env.feature.activate()
        env.audio.emit(started("com.apple.audio.coreaudiod", pid: 1, at: env.clock.now))
        env.audio.emit(started("com.apple.Safari", pid: 12, at: env.clock.now))
        await env.waitUntil { env.feature.current.contains { $0.bundleID == "com.apple.Safari" } }

        let message = await env.feature.mute(bundleID: nil)
        #expect(env.muting.muted == [12])
        #expect(message.contains("Safari"))
    }

    @Test func muteSystemIsRefused() async throws {
        let env = Environment()
        try await env.feature.activate()
        env.audio.emit(started("com.apple.controlcenter", pid: 8, at: env.clock.now))
        await env.waitUntil {
            env.feature.current.contains { $0.bundleID == "com.apple.controlcenter" }
        }

        let message = await env.feature.mute(bundleID: "com.apple.controlcenter")
        #expect(env.muting.muted.isEmpty)
        #expect(message.contains("системный"))
    }

    @Test func quitWithoutArgumentDoesNotTerminate() {
        let env = Environment()
        let message = env.feature.quit(bundleID: nil)
        #expect(env.apps.terminated.isEmpty)
        #expect(message.contains("укажите"))
    }

    @Test func denyListIsNotTerminated() {
        let env = Environment()
        let message = env.feature.quit(bundleID: "com.apple.finder")
        #expect(env.apps.terminated.isEmpty)
        #expect(message.contains("нельзя"))
    }

    @Test func deactivateUnmutes() async throws {
        let env = Environment()
        try await env.feature.activate()
        env.audio.emit(started("com.apple.Safari", pid: 12, at: env.clock.now))
        await env.waitUntil { env.feature.current.contains { $0.bundleID == "com.apple.Safari" } }
        _ = await env.feature.mute(bundleID: "com.apple.Safari")
        await env.feature.deactivate()

        #expect(env.muting.unmuteAllCount == 1)
        #expect(env.feature.mutedBundleIDs.isEmpty)
    }

    @Test func muteFailureAsksForAudioCapture() async throws {
        let env = Environment()
        env.muting.error = AudioMuteError.failed(1)
        try await env.feature.activate()
        env.audio.emit(started("com.apple.Safari", pid: 12, at: env.clock.now))
        await env.waitUntil { env.feature.current.contains { $0.bundleID == "com.apple.Safari" } }

        _ = await env.feature.mute(bundleID: "com.apple.Safari")
        #expect(env.feature.muteNeedsAudioCapture)
    }

    private func started(_ bundleID: String, pid: pid_t, at: Date) -> AudioOutputChange {
        AudioOutputChange(
            kind: .started,
            process: AudioOutputProcess(
                objectID: AudioObjectID(UInt32(pid)),
                pid: pid,
                bundleID: bundleID,
                deviceName: "Динамики",
                isRunningOutput: true
            ),
            at: at
        )
    }

    private func stopped(_ bundleID: String, pid: pid_t, at: Date) -> AudioOutputChange {
        AudioOutputChange(
            kind: .stopped,
            process: AudioOutputProcess(
                objectID: AudioObjectID(UInt32(pid)),
                pid: pid,
                bundleID: bundleID,
                deviceName: "Динамики",
                isRunningOutput: false
            ),
            at: at
        )
    }
}

@MainActor
private final class Environment {
    let clock = FakeClock()
    let audio = FakeAudioOutput()
    let muting = FakeMuting()
    let apps = FakeRunningApps()
    let feature: SoundsFeature

    init() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "sidekick-sounds-\(UUID().uuidString)", directoryHint: .isDirectory)
        feature = SoundsFeature(
            context: TestFeatureContext.make(id: "sounds"),
            clock: clock,
            audio: audio,
            muting: muting,
            apps: apps,
            notifier: FakeNotifier(),
            permissions: FakePermissions([.notifications: .granted]),
            historyDirectory: directory
        )
    }

    func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<40 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class FakeAudioOutput: AudioOutputObserving, @unchecked Sendable {
    private var continuation: AsyncStream<AudioOutputChange>.Continuation?
    private var pending: [AudioOutputChange] = []
    private var playing: [pid_t: AudioOutputProcess] = [:]

    func snapshot() -> [AudioOutputProcess] {
        Array(playing.values)
    }

    func events() -> AsyncStream<AudioOutputChange> {
        AsyncStream { continuation in
            self.continuation = continuation
            for change in pending {
                continuation.yield(change)
            }
            pending.removeAll()
        }
    }

    func seed(_ process: AudioOutputProcess) {
        playing[process.pid] = process
    }

    func emit(_ change: AudioOutputChange) {
        switch change.kind {
        case .started:
            playing[change.process.pid] = change.process
        case .stopped:
            playing.removeValue(forKey: change.process.pid)
        }

        if let continuation {
            continuation.yield(change)
        } else {
            pending.append(change)
        }
    }
}

private final class FakeMuting: AudioProcessMuting, @unchecked Sendable {
    var muted: [pid_t] = []
    var unmuteAllCount = 0
    var error: Error?

    func mute(pid: pid_t) throws {
        if let error { throw error }
        muted.append(pid)
    }

    func unmute(pid: pid_t) {
        muted.removeAll { $0 == pid }
    }

    func unmuteAll() {
        unmuteAllCount += 1
        muted.removeAll()
    }
}

private final class FakeRunningApps: RunningApplications, @unchecked Sendable {
    var terminated: [String] = []

    func localizedName(for bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Safari": "Safari"
        case "com.apple.Music": "Музыка"
        default: nil
        }
    }

    func activate(bundleID: String) {}

    func terminate(bundleID: String) -> Bool {
        terminated.append(bundleID)
        return true
    }

    func open(url: URL) {}
}

private struct FakeNotifier: UserNotifying {
    func notify(title: String, body: String) async {}
}
