import AppCore
import Foundation
import Observation
import PermissionsKit
import SwiftUI
import SystemKit

/// Shows who holds the audio output and can mute or quit that app.
@MainActor
@Observable
public final class SoundsFeature: Feature {
    public static let descriptor = FeatureDescriptor(
        id: "sounds",
        title: "Кто шумит",
        summary:
            "Показывает, какое приложение сейчас или недавно держало звук, и даёт его выключить",
        symbolName: "speaker.wave.2",
        requiredPermissions: [],
        isEnabledByDefault: false
    )

    private(set) var current: [OutputSource] = []
    private(set) var recent: [OutputSource] = []
    private(set) var mutedBundleIDs: Set<String> = []
    private(set) var muteNeedsAudioCapture = false
    private(set) var notifyOnStart: Bool
    private(set) var recentMinutes: Int
    private(set) var hideSystem: Bool

    private let context: FeatureContext
    private let clock: any Clock
    private let audio: any AudioOutputObserving
    private let muting: any AudioProcessMuting
    private let apps: any RunningApplications
    private let notifier: any UserNotifying
    private let permissions: any PermissionChecking
    private let historyURL: URL
    private var history = OutputHistory()
    private var listenTask: Task<Void, Never>?

    public convenience init(context: FeatureContext) {
        self.init(
            context: context,
            clock: SystemClock(),
            audio: LiveAudioOutputObserver(),
            muting: LiveAudioProcessMuter(),
            apps: LiveRunningApplications(),
            notifier: LiveUserNotifier(),
            permissions: LivePermissionChecker()
        )
    }

    init(
        context: FeatureContext,
        clock: any Clock,
        audio: any AudioOutputObserving,
        muting: any AudioProcessMuting,
        apps: any RunningApplications,
        notifier: any UserNotifying,
        permissions: any PermissionChecking,
        historyDirectory: URL? = nil
    ) {
        self.context = context
        self.clock = clock
        self.audio = audio
        self.muting = muting
        self.apps = apps
        self.notifier = notifier
        self.permissions = permissions
        self.notifyOnStart = context.settings.value(for: Keys.notifyOnStart)
        self.recentMinutes = context.settings.value(for: Keys.recentMinutes)
        self.hideSystem = context.settings.value(for: Keys.hideSystem)

        let directory =
            historyDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "com.hugly.sidekick", directoryHint: .isDirectory)
            ?? FileManager.default.temporaryDirectory
        self.historyURL = directory.appending(path: "sounds-history.json")
    }

    public func activate() async throws {
        history.load(from: historyURL, now: clock.now)
        for process in audio.snapshot() {
            history.started(
                bundleID: process.bundleID,
                pid: process.pid,
                deviceName: process.deviceName,
                at: clock.now
            )
        }
        refresh()
        persist()

        listenTask = Task { [weak self] in
            guard let self else { return }
            for await change in self.audio.events() {
                await self.handle(change)
            }
        }

        context.log.info("Activated")
    }

    public func deactivate() async {
        listenTask?.cancel()
        listenTask = nil
        muting.unmuteAll()
        mutedBundleIDs.removeAll()
        persist()
    }

    func title(for source: OutputSource) -> String {
        if source.isSystem {
            return apps.localizedName(for: source.bundleID) ?? "Системный звук"
        }
        return apps.localizedName(for: source.bundleID) ?? source.bundleID
    }

    func relativeDescription(for source: OutputSource) -> String {
        source.relativeDescription(now: clock.now)
    }

    func setNotifyOnStart(_ value: Bool) {
        notifyOnStart = value
        context.settings.set(value, for: Keys.notifyOnStart)
        if value {
            Task { _ = await permissions.request(.notifications) }
        }
    }

    func setRecentMinutes(_ value: Int) {
        recentMinutes = max(1, value)
        context.settings.set(recentMinutes, for: Keys.recentMinutes)
        refresh()
    }

    func setHideSystem(_ value: Bool) {
        hideSystem = value
        context.settings.set(value, for: Keys.hideSystem)
        refresh()
    }

    func openSoundSettings() -> String {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            apps.open(url: url)
        }
        return "открываю настройки звука"
    }

    func openAudioCaptureSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) {
            apps.open(url: url)
        }
    }

    func mute(bundleID argument: String?) async -> String {
        guard let bundleID = resolvedBundleID(argument) else {
            return "сейчас никто не играет"
        }
        guard SystemAudioIdentity.allowsMute(bundleID) else {
            return "системный звук нельзя замьютить"
        }

        let pids = history.pids(for: bundleID)
        guard !pids.isEmpty else { return "источник не найден" }

        do {
            for pid in pids {
                try muting.mute(pid: pid)
            }
            mutedBundleIDs.insert(bundleID)
            return "замьючен \(displayName(bundleID))"
        } catch {
            muteNeedsAudioCapture = true
            return error.localizedDescription
        }
    }

    func unmute(bundleID argument: String?) -> String {
        guard let bundleID = resolvedBundleID(argument) else {
            return "нечего включать"
        }

        for pid in history.pids(for: bundleID) {
            muting.unmute(pid: pid)
        }
        mutedBundleIDs.remove(bundleID)
        return "звук \(displayName(bundleID)) включён"
    }

    func quit(bundleID argument: String?) -> String {
        guard let bundleID = argument, !bundleID.isEmpty else {
            return "укажите приложение"
        }
        guard SystemAudioIdentity.allowsQuit(bundleID) else {
            return "это приложение закрывать нельзя"
        }

        let name = displayName(bundleID)
        return apps.terminate(bundleID: bundleID)
            ? "закрываю \(name)" : "не удалось закрыть \(name)"
    }

    func activateApp(bundleID: String) {
        apps.activate(bundleID: bundleID)
    }

    private func handle(_ change: AudioOutputChange) async {
        switch change.kind {
        case .started:
            let wasCurrent = history.source(bundleID: change.process.bundleID)?.isPlaying == true
            history.started(
                bundleID: change.process.bundleID,
                pid: change.process.pid,
                deviceName: change.process.deviceName,
                at: change.at
            )
            await context.events.publish(
                AudioOutputStarted(
                    bundleID: change.process.bundleID,
                    pid: change.process.pid,
                    deviceName: change.process.deviceName,
                    at: change.at
                )
            )
            if !wasCurrent {
                await notifyIfNeeded(change.process)
            }
        case .stopped:
            history.stopped(
                bundleID: change.process.bundleID,
                pid: change.process.pid,
                at: change.at
            )
            await context.events.publish(
                AudioOutputStopped(
                    bundleID: change.process.bundleID,
                    pid: change.process.pid,
                    at: change.at
                )
            )
        }

        refresh()
        persist()
    }

    private func notifyIfNeeded(_ process: AudioOutputProcess) async {
        guard notifyOnStart else { return }
        guard !hideSystem || !SystemAudioIdentity.isSystem(bundleID: process.bundleID) else {
            return
        }

        let status = await permissions.request(.notifications)
        guard status == .granted else { return }

        let name =
            SystemAudioIdentity.isSystem(bundleID: process.bundleID)
            ? "Системный звук"
            : (apps.localizedName(for: process.bundleID) ?? process.bundleID)
        await notifier.notify(title: "Кто шумит", body: name)
    }

    private func refresh() {
        reconcileFromSnapshot()
        let since = clock.now.addingTimeInterval(-TimeInterval(recentMinutes * 60))
        current = history.current(hidingSystem: hideSystem)
        recent = history.recent(since: since, hidingSystem: hideSystem)
    }

    /// HAL listeners miss short sounds and some apps. Snapshot is who is
    /// actually holding the output right now.
    private func reconcileFromSnapshot() {
        let playing = audio.snapshot()
        let keys = Set(playing.map(Self.historyKey))

        for process in playing {
            history.started(
                bundleID: process.bundleID,
                pid: process.pid,
                deviceName: process.deviceName,
                at: clock.now
            )
        }

        for source in history.current(hidingSystem: false)
        where !keys.contains(Self.historyKey(source)) {
            history.stopped(bundleID: source.bundleID, pid: source.pid, at: clock.now)
        }
    }

    private static func historyKey(_ process: AudioOutputProcess) -> String {
        process.bundleID.isEmpty ? "pid:\(process.pid)" : process.bundleID
    }

    private static func historyKey(_ source: OutputSource) -> String {
        source.bundleID.isEmpty ? "pid:\(source.pid)" : source.bundleID
    }

    private func persist() {
        history.save(to: historyURL, now: clock.now)
    }

    private func resolvedBundleID(_ argument: String?) -> String? {
        if let argument, !argument.isEmpty { return argument }
        return history.latestNonSystem()?.bundleID
    }

    private func displayName(_ bundleID: String) -> String {
        if SystemAudioIdentity.isSystem(bundleID: bundleID) {
            return "системный звук"
        }
        return apps.localizedName(for: bundleID) ?? bundleID
    }

    private func statusText() -> String {
        refresh()
        if current.isEmpty, recent.isEmpty {
            return "сейчас никто не играет"
        }

        let playing = current.map { source in
            "сейчас: \(title(for: source)) · \(source.deviceName) · \(relativeDescription(for: source))"
        }
        let stopped = recent.map { source in
            "недавно: \(title(for: source)) · \(relativeDescription(for: source))"
        }
        return (playing + stopped).joined(separator: "\n")
    }

    private enum Keys {
        static let notifyOnStart = SettingKey("notifyOnStart", default: false)
        static let recentMinutes = SettingKey("recentMinutes", default: 15)
        static let hideSystem = SettingKey("hideSystem", default: false)
    }
}

extension SoundsFeature {
    public var commands: [Command] {
        [
            Command(id: "sounds.status", title: "Кто шумит", symbolName: "speaker.wave.2") { _ in
                self.statusText()
            },
            Command(
                id: "sounds.mute",
                title: "Замьютить последний источник",
                symbolName: "speaker.slash"
            ) { argument in
                await self.mute(bundleID: argument)
            },
            Command(
                id: "sounds.unmute",
                title: "Включить звук последнего источника",
                symbolName: "speaker.wave.2"
            ) { argument in
                self.unmute(bundleID: argument)
            },
            Command(id: "sounds.quit", title: "Закрыть приложение", symbolName: "xmark") {
                argument in
                self.quit(bundleID: argument)
            },
            Command(
                id: "sounds.open-settings",
                title: "Открыть настройки звука",
                symbolName: "slider.horizontal.3"
            ) { _ in
                self.openSoundSettings()
            },
        ]
    }

    public func makeMenuView() -> AnyView? {
        AnyView(SoundsMenuView(feature: self))
    }

    public func makeSettingsView() -> AnyView {
        AnyView(SoundsSettingsView(feature: self))
    }
}
