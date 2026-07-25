import Foundation

/// Pure assembly of the audio-input picker's selectable values. The stored value
/// is the env value written to `STT_AUDIO_DEVICE`: `""` means "let the backend
/// auto-pick" (the default), any other string is a CoreAudio input device name —
/// matched by `AudioInputResolver` natively and passed to `sox -t coreaudio` by
/// the shell backend.
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

/// Enumerates the current audio input devices. The names come from CoreAudio —
/// the same source `AudioInputResolver` matches against and the same names
/// `sox -t coreaudio` expects. Listing devices from one source and resolving
/// them from another is how a saved selection silently stops applying.
enum AudioInputDevices {
    static func available() -> [String] {
        // Preserve HAL order but drop duplicates (a device can surface twice).
        var seen = Set<String>()
        return AudioDevices.inputs().map(\.name).filter { seen.insert($0).inserted }
    }
}
