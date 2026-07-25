import CoreAudio
import Foundation

/// How a device is attached. Only the distinction that matters for recording is
/// modelled: Bluetooth inputs force the headset into the bidirectional HFP
/// profile, which audibly degrades whatever is playing back at the same time.
enum AudioInputTransport: Equatable {
    case builtIn
    case usb
    case bluetooth
    case other

    init(rawTransport: UInt32) {
        switch rawTransport {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        default: self = .other
        }
    }
}

/// A recordable input device. A value type so `AudioInputResolver` can be
/// exercised without any CoreAudio hardware present.
struct AudioInputDeviceInfo: Equatable {
    let id: AudioDeviceID
    let name: String
    let transport: AudioInputTransport
}

/// Reads the CoreAudio HAL device list. Every property read is best-effort: a
/// device that refuses to answer is skipped rather than failing the enumeration,
/// because a partial device list still lets recording proceed.
enum AudioDevices {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// All devices that can actually record, in HAL order.
    static func inputs() -> [AudioInputDeviceInfo] {
        deviceIDs().compactMap { id in
            guard inputChannelCount(id) > 0, let name = name(of: id) else { return nil }
            return AudioInputDeviceInfo(id: id, name: name, transport: transport(of: id))
        }
    }

    /// The device an unconfigured `AVAudioEngine` would record from.
    static func defaultInput() -> AudioInputDeviceInfo? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown, let name = name(of: id) else { return nil }
        return AudioInputDeviceInfo(id: id, name: name, transport: transport(of: id))
    }

    // MARK: Property reads

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        let name = (value as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func transport(of id: AudioDeviceID) -> AudioInputTransport {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var raw = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &raw) == noErr else { return .other }
        return AudioInputTransport(rawTransport: raw)
    }

    /// Sums the channels of every input stream. Output-only devices report 0 and
    /// are what separates a speaker from a microphone in the HAL device list.
    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
