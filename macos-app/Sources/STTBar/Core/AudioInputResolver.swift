import CoreAudio
import Foundation

/// Which device the recorder should bind to.
enum AudioInputResolution: Equatable {
    /// Leave the engine on whatever CoreAudio considers the default input.
    case systemDefault
    /// Pin the engine to this device.
    case device(AudioDeviceID)
}

/// Picks the recording input. Pure over value types so every rule is testable
/// without audio hardware.
///
/// Recording from a Bluetooth headset forces macOS to switch it from A2DP
/// playback into the bidirectional HFP profile: music turns dull and the volume
/// jumps. `stt-record.sh` has avoided this since `092e014`; this type restores
/// the same behavior for the native pipeline that replaced it.
enum AudioInputResolver {
    static func resolve(selected: String,
                        avoidBluetooth: Bool,
                        devices: [AudioInputDeviceInfo],
                        defaultInput: AudioInputDeviceInfo?) -> AudioInputResolution {
        // An explicit pick wins outright, Bluetooth included — someone who
        // chooses their headset in the picker means it.
        let wanted = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !wanted.isEmpty,
           let match = devices.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) {
            return .device(match.id)
        }

        // Nothing picked, or the picked device is unplugged. Falling back to the
        // system default here is what silently lands on the headset, so the
        // guard runs in both cases.
        guard avoidBluetooth, let current = defaultInput, current.transport == .bluetooth else {
            return .systemDefault
        }

        let wired = devices.first { $0.transport == .builtIn }
            ?? devices.first { $0.transport == .usb }
            ?? devices.first { $0.transport != .bluetooth }
        // A Bluetooth-only machine still gets to record: poor quality beats none.
        guard let wired else { return .systemDefault }
        return .device(wired.id)
    }

    /// Resolves against the devices currently attached to this machine.
    static func resolveLive(selected: String, avoidBluetooth: Bool) -> AudioInputResolution {
        resolve(selected: selected,
                avoidBluetooth: avoidBluetooth,
                devices: AudioDevices.inputs(),
                defaultInput: AudioDevices.defaultInput())
    }

    /// Names the microphone a run actually recorded from. Without this the log
    /// only shows how long resolution took, so after the fact there is no way
    /// to tell which input a bad transcript came through.
    static func logLabel(for resolution: AudioInputResolution,
                         devices: [AudioInputDeviceInfo],
                         defaultInput: AudioInputDeviceInfo?) -> String {
        func describe(_ device: AudioInputDeviceInfo?, fallback: String, source: String) -> String {
            guard let device else { return "device=\(fallback) transport=unknown source=\(source)" }
            return "device=\"\(device.name)\" transport=\(device.transport.logName) source=\(source)"
        }
        switch resolution {
        case .device(let id):
            return describe(devices.first { $0.id == id }, fallback: "id:\(id)", source: "pinned")
        case .systemDefault:
            return describe(defaultInput, fallback: "unknown", source: "systemDefault")
        }
    }

    /// Resolves and labels in one pass so the log names the same device list the
    /// recorder binds to.
    static func resolveLiveWithLabel(selected: String,
                                     avoidBluetooth: Bool) -> (AudioInputResolution, String) {
        let devices = AudioDevices.inputs()
        let defaultInput = AudioDevices.defaultInput()
        let resolution = resolve(selected: selected, avoidBluetooth: avoidBluetooth,
                                 devices: devices, defaultInput: defaultInput)
        return (resolution, logLabel(for: resolution, devices: devices, defaultInput: defaultInput))
    }
}
