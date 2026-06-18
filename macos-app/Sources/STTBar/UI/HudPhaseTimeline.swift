import Foundation

struct HudPhaseDurations: Equatable {
    var recording: TimeInterval?
    var whisper: TimeInterval?
    var llm: TimeInterval?
    var total: TimeInterval
}

struct HudPhaseTimeline: Equatable {
    private(set) var runStartedAt: Date?
    private(set) var recordingStartedAt: Date?
    private(set) var recordingEndedAt: Date?
    private(set) var whisperStartedAt: Date?
    private(set) var whisperEndedAt: Date?
    private(set) var llmStartedAt: Date?

    mutating func reset() {
        self = HudPhaseTimeline()
    }

    mutating func transition(to newState: SttState, from oldState: SttState, at now: Date) {
        switch newState {
        case .recording:
            if oldState == .idle || oldState == .error || runStartedAt == nil || recordingEndedAt != nil {
                startRecording(at: now)
            }
        case .whisper:
            ensureRunStarted(at: now)
            if recordingStartedAt == nil { recordingStartedAt = runStartedAt }
            if recordingEndedAt == nil { recordingEndedAt = now }
            if whisperStartedAt == nil { whisperStartedAt = now }
        case .llm:
            ensureRunStarted(at: now)
            if recordingStartedAt == nil { recordingStartedAt = runStartedAt }
            if recordingEndedAt == nil { recordingEndedAt = whisperStartedAt ?? now }
            if whisperStartedAt == nil { whisperStartedAt = recordingEndedAt }
            if whisperEndedAt == nil { whisperEndedAt = now }
            if llmStartedAt == nil { llmStartedAt = now }
        case .idle:
            if oldState == .idle { reset() }
        case .error:
            ensureRunStarted(at: now)
        }
    }

    func durations(at now: Date, state: SttState) -> HudPhaseDurations {
        let recording = duration(from: recordingStartedAt,
                                 to: recordingEndedAt ?? (state == .recording ? now : nil))
        let whisper = duration(from: whisperStartedAt,
                               to: whisperEndedAt ?? (state == .whisper ? now : nil))
        let llm = duration(from: llmStartedAt,
                           to: state == .llm ? now : nil)
        let total = duration(from: runStartedAt, to: now) ?? 0
        return HudPhaseDurations(recording: recording, whisper: whisper, llm: llm, total: total)
    }

    private mutating func startRecording(at now: Date) {
        runStartedAt = now
        recordingStartedAt = now
        recordingEndedAt = nil
        whisperStartedAt = nil
        whisperEndedAt = nil
        llmStartedAt = nil
    }

    private mutating func ensureRunStarted(at now: Date) {
        if runStartedAt == nil { runStartedAt = now }
    }

    private func duration(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        return max(0, end.timeIntervalSince(start))
    }
}
