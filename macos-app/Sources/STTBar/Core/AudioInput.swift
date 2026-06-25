import AVFoundation

/// Pure assembly of the audio-input picker's selectable values. The stored value
/// is the env value written to `STT_AUDIO_DEVICE` (which `stt-record.sh` honors):
/// `""` means "let the backend auto-pick" (the default), any other string is a
/// CoreAudio input device name passed to `sox -t coreaudio`.
enum AudioInputCatalog {
    /// Env value representing automatic device selection.
    static let automatic = ""

    /// Ordered, de-duplicated selectable env values: automatic first, then each
    /// available device, then `current` if it is a real device that is no longer
    /// in `available` (e.g. unplugged) so a saved selection is never lost.
    static func deviceIds(available: [String], current: String) -> [String] {
        var ids = [automatic]
        for name in available where !name.isEmpty && !ids.contains(name) {
            ids.append(name)
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !ids.contains(trimmed) {
            ids.append(trimmed)
        }
        return ids
    }
}

/// Enumerates the current audio input devices. The `localizedName` is the value
/// `sox -t coreaudio` expects, so it is what we store in `STT_AUDIO_DEVICE`.
enum AudioInputDevices {
    static func available() -> [String] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified)
        // Preserve discovery order but drop duplicates (a device can surface twice).
        var seen = Set<String>()
        return session.devices.map(\.localizedName).filter { seen.insert($0).inserted }
    }
}
