import Foundation

/// What a single hotkey press should do, decided from ground truth instead of
/// re-derived independently by the shell.
enum SttToggleAction: Equatable {
    /// Begin a fresh recording now (after cleaning any stale leftovers).
    case start
    /// Stop the live recording and transcribe.
    case stop
    /// A previous run is still finishing (no live audio): remember the press
    /// and start a fresh recording as soon as it completes.
    case queueStart
    /// Too soon after the previous press (debounce) — drop it.
    case ignore
}

/// Pure decision logic for the start/stop hotkey. The core rule the user asked
/// for: if no recording is genuinely live (zero audio signal), the press is a
/// start, never an accidental stop. A live recording is the only thing that
/// turns a press into a stop. Rapid re-fires within `debounce` are ignored so a
/// single physical press (or a duplicated global-hotkey event) cannot both
/// start and immediately stop.
struct RecordingToggle {
    var debounce: TimeInterval = 0.35

    func decide(isLiveRecording: Bool, isBusy: Bool, lastTriggerAt: Date?, now: Date) -> SttToggleAction {
        if let last = lastTriggerAt, now.timeIntervalSince(last) < debounce {
            return .ignore
        }
        if isLiveRecording {
            return .stop
        }
        if isBusy {
            return .queueStart
        }
        return .start
    }
}
