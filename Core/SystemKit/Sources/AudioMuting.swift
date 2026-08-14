import CoreAudio
import Foundation

public enum AudioMuteError: Error, LocalizedError, Sendable {
    case processUnknown
    case failed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .processUnknown:
            "процесс больше не играет"
        case .failed(let status):
            "не удалось замьютить (код \(status)). Нужно разрешение на запись системного звука"
        }
    }
}

/// Per-process mute via a private HAL tap. Not a mixer and not a global mute.
public protocol AudioProcessMuting: Sendable {
    func mute(pid: pid_t) throws
    func unmute(pid: pid_t)
    func unmuteAll()
}

public final class LiveAudioProcessMuter: AudioProcessMuting, @unchecked Sendable {
    private struct Session {
        let tapID: AudioObjectID
        let aggregateID: AudioObjectID

        func tearDown() {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
        }
    }

    private let lock = NSLock()
    private var sessions: [pid_t: Session] = [:]
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private let queue = DispatchQueue(label: "com.hugly.sidekick.audio-mute")

    public init() {}

    deinit {
        unmuteAll()
        removeDeviceListener()
    }

    public func mute(pid: pid_t) throws {
        lock.lock()
        let alreadyMuted = sessions[pid] != nil
        lock.unlock()
        if alreadyMuted { return }

        guard let processObject = HAL.processObject(forPID: pid) else {
            throw AudioMuteError.processUnknown
        }

        let tapID = try createTap(for: processObject)
        do {
            let aggregateID = try createAggregate(tapID: tapID)
            lock.lock()
            if sessions[pid] != nil {
                lock.unlock()
                AudioHardwareDestroyAggregateDevice(aggregateID)
                AudioHardwareDestroyProcessTap(tapID)
                return
            }
            sessions[pid] = Session(tapID: tapID, aggregateID: aggregateID)
            lock.unlock()
            installDeviceListener()
        } catch {
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
    }

    public func unmute(pid: pid_t) {
        lock.lock()
        let session = sessions.removeValue(forKey: pid)
        lock.unlock()
        session?.tearDown()
    }

    public func unmuteAll() {
        lock.lock()
        let all = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        for session in all {
            session.tearDown()
        }
        removeDeviceListener()
    }

    private func createTap(for processObject: AudioObjectID) throws -> AudioObjectID {
        let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
        description.isPrivate = true
        description.muteBehavior = .muted
        description.uuid = UUID()
        description.name = "Sidekick mute"

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else {
            throw AudioMuteError.failed(status)
        }
        return tapID
    }

    private func createAggregate(tapID: AudioObjectID) throws -> AudioObjectID {
        guard let tapUID = HAL.tapUID(of: tapID) else {
            throw AudioMuteError.failed(kAudioHardwareUnknownPropertyError)
        }

        let dictionary: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sidekick Mute",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID]
            ],
        ]

        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(dictionary as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != kAudioObjectUnknown else {
            throw AudioMuteError.failed(status)
        }
        return aggregateID
    }

    private func installDeviceListener() {
        lock.lock()
        let already = deviceBlock != nil
        lock.unlock()
        if already { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.recreateAll()
        }
        lock.lock()
        deviceBlock = block
        lock.unlock()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            block
        )
    }

    private func removeDeviceListener() {
        lock.lock()
        let block = deviceBlock
        deviceBlock = nil
        lock.unlock()
        guard let block else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            block
        )
    }

    private func recreateAll() {
        lock.lock()
        let pids = Array(sessions.keys)
        lock.unlock()
        for pid in pids {
            unmute(pid: pid)
            try? mute(pid: pid)
        }
    }
}
