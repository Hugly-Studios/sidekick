import CoreAudio
import Foundation

/// Small Core Audio property reads used by the output observer and process muter.
enum HAL {
    static func processObjectIDs() -> [AudioObjectID] {
        array(
            object: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessObjectList,
            type: AudioObjectID.self
        )
    }

    static func processObject(forPID pid: pid_t) -> AudioObjectID? {
        var qualifier = pid
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &qualifier,
            &size,
            &objectID
        )
        guard status == noErr, objectID != kAudioObjectUnknown else { return nil }
        return objectID
    }

    static func process(id objectID: AudioObjectID) -> AudioOutputProcess? {
        guard let pid: pid_t = value(object: objectID, selector: kAudioProcessPropertyPID) else {
            return nil
        }

        let running: UInt32 =
            value(object: objectID, selector: kAudioProcessPropertyIsRunningOutput) ?? 0
        let bundleID = string(object: objectID, selector: kAudioProcessPropertyBundleID) ?? ""
        let devices: [AudioObjectID] = array(
            object: objectID,
            selector: kAudioProcessPropertyDevices,
            type: AudioObjectID.self
        )
        let deviceName =
            devices
            .compactMap { string(object: $0, selector: kAudioObjectPropertyName) }
            .first { !$0.isEmpty }
            ?? defaultOutputDeviceName()
            ?? ""

        return AudioOutputProcess(
            objectID: objectID,
            pid: pid,
            bundleID: bundleID,
            deviceName: deviceName,
            isRunningOutput: running != 0
        )
    }

    static func tapUID(of tapID: AudioObjectID) -> String? {
        string(object: tapID, selector: kAudioTapPropertyUID)
    }

    static func defaultOutputDeviceName() -> String? {
        guard
            let deviceID: AudioObjectID = value(
                object: AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyDefaultOutputDevice
            ),
            deviceID != kAudioObjectUnknown
        else { return nil }
        return string(object: deviceID, selector: kAudioObjectPropertyName)
    }

    private static func value<T>(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(object, &address) else { return nil }

        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer {
            pointer.deinitialize(count: 1)
            pointer.deallocate()
        }

        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        guard status == noErr else { return nil }
        return pointer.pointee
    }

    private static func string(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(object, &address) else { return nil }

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0
        else {
            return nil
        }

        let pointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        pointer.initialize(to: nil)
        defer {
            pointer.deinitialize(count: 1)
            pointer.deallocate()
        }

        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        guard status == noErr, let cfString = pointer.pointee else { return nil }
        return cfString as String
    }

    private static func array<T>(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        type _: T.Type
    ) -> [T] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(object, &address) else { return [] }

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0
        else {
            return []
        }

        let count = Int(size) / MemoryLayout<T>.stride
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer {
            pointer.deinitialize(count: count)
            pointer.deallocate()
        }

        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        guard status == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
}
