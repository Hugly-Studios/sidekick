import AppCore
import CoreAudio
import Foundation

/// A HAL process object that can hold the default output.
public struct AudioOutputProcess: Sendable, Equatable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String
    public let deviceName: String
    public let isRunningOutput: Bool

    public init(
        objectID: AudioObjectID,
        pid: pid_t,
        bundleID: String,
        deviceName: String,
        isRunningOutput: Bool
    ) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.deviceName = deviceName
        self.isRunningOutput = isRunningOutput
    }
}

public struct AudioOutputChange: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case started
        case stopped
    }

    public let kind: Kind
    public let process: AudioOutputProcess
    public let at: Date

    public init(kind: Kind, process: AudioOutputProcess, at: Date) {
        self.kind = kind
        self.process = process
        self.at = at
    }
}

public struct AudioOutputStarted: AppEvent, Sendable {
    public let bundleID: String
    public let pid: pid_t
    public let deviceName: String
    public let at: Date

    public init(bundleID: String, pid: pid_t, deviceName: String, at: Date) {
        self.bundleID = bundleID
        self.pid = pid
        self.deviceName = deviceName
        self.at = at
    }
}

public struct AudioOutputStopped: AppEvent, Sendable {
    public let bundleID: String
    public let pid: pid_t
    public let at: Date

    public init(bundleID: String, pid: pid_t, at: Date) {
        self.bundleID = bundleID
        self.pid = pid
        self.at = at
    }
}

/// Who is registered for audio output, via HAL process objects — not polling.
public protocol AudioOutputObserving: Sendable {
    func snapshot() -> [AudioOutputProcess]
    func events() -> AsyncStream<AudioOutputChange>
}

public struct LiveAudioOutputObserver: AudioOutputObserving {
    public init() {}

    public func snapshot() -> [AudioOutputProcess] {
        HAL.processObjectIDs().compactMap(HAL.process(id:)).filter(\.isRunningOutput)
    }

    public func events() -> AsyncStream<AudioOutputChange> {
        AsyncStream { continuation in
            let session = OutputListenSession { change in
                continuation.yield(change)
            }
            session.start()
            continuation.onTermination = { _ in session.stop() }
        }
    }
}

private final class OutputListenSession: @unchecked Sendable {
    private let onChange: @Sendable (AudioOutputChange) -> Void
    private let queue = DispatchQueue(label: "com.hugly.sidekick.audio-output")
    private let lock = NSLock()
    private var running: [AudioObjectID: AudioOutputProcess] = [:]
    private var processBlock: AudioObjectPropertyListenerBlock?
    private var listBlock: AudioObjectPropertyListenerBlock?
    private var listenStartedAt: [AudioObjectID: Date] = [:]
    private var started = false

    init(onChange: @escaping @Sendable (AudioOutputChange) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async { [weak self] in
            self?.install()
        }
    }

    func stop() {
        queue.sync { [weak self] in
            self?.tearDown()
        }
    }

    private func install() {
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        let list: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refresh(emitTransitions: true)
        }
        let process: AudioObjectPropertyListenerBlock = { [weak self] objectID, _ in
            self?.processChanged(objectID)
        }
        listBlock = list
        processBlock = process
        addListener(
            object: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessObjectList,
            block: list
        )
        refresh(emitTransitions: false)
        scheduleRescan()
    }

    private func tearDown() {
        if let listBlock {
            removeListener(
                object: AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyProcessObjectList,
                block: listBlock
            )
        }
        if let processBlock {
            for objectID in running.keys {
                removeProcessListeners(objectID, block: processBlock)
            }
        }
        listBlock = nil
        processBlock = nil
        running.removeAll()
        listenStartedAt.removeAll()
        started = false
    }

    private func refresh(emitTransitions: Bool) {
        let ids = Set(HAL.processObjectIDs())
        let known = Set(running.keys)
        guard let processBlock else { return }

        for objectID in ids.subtracting(known) {
            listenStartedAt[objectID] = Date()
            addProcessListeners(objectID, block: processBlock)
            if let current = HAL.process(id: objectID) {
                apply(current, shouldEmit: emitTransitions, allowPulse: false)
            }
        }

        for objectID in known.subtracting(ids) {
            removeProcessListeners(objectID, block: processBlock)
            listenStartedAt.removeValue(forKey: objectID)
            if let previous = running.removeValue(forKey: objectID), previous.isRunningOutput {
                publish(.stopped, previous)
            }
        }
    }

    private func processChanged(_ objectID: AudioObjectID) {
        queue.async { [weak self] in
            guard let current = HAL.process(id: objectID) else { return }
            let added = self?.listenStartedAt[objectID] ?? .distantPast
            let allowPulse = Date().timeIntervalSince(added) > 0.5
            self?.apply(current, shouldEmit: true, allowPulse: allowPulse)
        }
    }

    private func scheduleRescan() {
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.started else { return }
            self.rescan()
            self.scheduleRescan()
        }
    }

    private func rescan() {
        refresh(emitTransitions: true)
        for objectID in Array(running.keys) {
            guard let current = HAL.process(id: objectID) else { continue }
            apply(current, shouldEmit: true, allowPulse: false)
        }
    }

    private func apply(
        _ current: AudioOutputProcess,
        shouldEmit: Bool,
        allowPulse: Bool
    ) {
        let previous = running[current.objectID]
        running[current.objectID] = current

        guard shouldEmit else { return }

        for kind in AudioOutputTransition.events(
            previousRunning: previous?.isRunningOutput,
            currentRunning: current.isRunningOutput,
            allowPulse: allowPulse
        ) {
            publish(kind, current)
        }
    }

    private func addProcessListeners(
        _ objectID: AudioObjectID,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        addListener(object: objectID, selector: kAudioProcessPropertyIsRunningOutput, block: block)
        addListener(object: objectID, selector: kAudioProcessPropertyIsRunning, block: block)
    }

    private func removeProcessListeners(
        _ objectID: AudioObjectID,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        removeListener(
            object: objectID,
            selector: kAudioProcessPropertyIsRunningOutput,
            block: block
        )
        removeListener(object: objectID, selector: kAudioProcessPropertyIsRunning, block: block)
    }

    private func publish(_ kind: AudioOutputChange.Kind, _ process: AudioOutputProcess) {
        onChange(AudioOutputChange(kind: kind, process: process, at: Date()))
    }

    private func addListener(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
    }

    private func removeListener(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }
}
