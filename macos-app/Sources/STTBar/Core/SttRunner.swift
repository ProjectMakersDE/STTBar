import Foundation

/// High-level state reported to the icon + HUD.
enum SttState { case idle, recording, whisper, llm, error }

struct WatchdogReport {
    var isRecording: Bool
    var duration: TimeInterval
    var stalePidRemoved: Bool
    var exceededLimit: Bool
}

/// Drives the STT pipeline via a `TranscriptionBackend`. First trigger starts
/// recording; second stops and transcribes. `onState` reports the high-level
/// state for icon + HUD. No shell process is ever spawned.
final class SttRunner {
    private let backend: TranscriptionBackend
    let phaseFilePath: String
    var onState: ((SttState) -> Void)?
    var onTranscript: ((String, SttMode, NativePasteResult) -> Void)?
    var onProblem: ((SttStatus) -> Void)?
    private var busy = false
    private var recordingStartedAt: Date?
    private(set) var state: SttState = .idle

    /// Single source of truth for the start/stop decision. Replaces the old
    /// implicit toggle that re-derived start-vs-stop independently in Swift and
    /// in the shell (which could diverge and mis-fire).
    private let toggle = RecordingToggle()
    private var lastTriggerAt: Date?
    /// Arrival time of the previous *raw* trigger event (accepted or ignored),
    /// used purely to measure double-fire spacing — not part of the decision.
    private var lastRawEventAt: Date?
    /// A press that arrived while a previous run was still finishing. Honored as
    /// a fresh start once that run completes, so a press is never silently lost.
    private var pendingStart = false
    private var pendingMode: SttMode = .full
    /// Mode of the recording currently in flight, so the watchdog can stop and
    /// transcribe a runaway recording without knowing how it was started.
    private var activeMode: SttMode = .full
    /// Bumped by cancelRecording. A stop completion captured under an older
    /// generation is stale (the user cancelled it) and must not paste.
    private var runGeneration = 0

    init(backend: TranscriptionBackend = PlaceholderBackend()) {
        self.backend = backend
        RuntimePaths.ensureDirectory()
        self.phaseFilePath = RuntimePaths.phaseFile.path
    }

    var isRecording: Bool { backend.isRecording }

    var recordingDuration: TimeInterval {
        guard let started = recordingStartedAt else { return 0 }
        return max(0, Date().timeIntervalSince(started))
    }

    /// `eventTime` is when the raw hotkey event arrived (stamped in the Carbon
    /// callback before the hop to main); nil for menu clicks. It feeds only the
    /// instrumentation, never the decision, so behavior is unchanged.
    func trigger(mode: SttMode, eventTime: Date? = nil) {
        let now = Date()
        let eventAt = eventTime ?? now
        let timing = TriggerTiming(previousRawEventAt: lastRawEventAt, eventAt: eventAt, handledAt: now)
        lastRawEventAt = eventAt
        let action = toggle.decide(isLiveRecording: isRecording, isBusy: busy, lastTriggerAt: lastTriggerAt, now: now)
        AppLogger.log("trigger mode=\(mode.rawValue) decided=\(action) isRecording=\(isRecording) busy=\(busy) dtMs=\(timing.intervalToken) latencyMs=\(timing.latencyMs)")
        if action == .ignore { return }
        lastTriggerAt = now
        switch action {
        case .queueStart:
            // A run is still finishing. The user's rule: this press is a start.
            // Remember it and fire once the run completes.
            pendingStart = true
            pendingMode = mode
        case .start:
            startRecording(mode: mode)
        case .stop:
            stopRecording(mode: mode)
        case .ignore:
            break
        }
    }

    private func startRecording(mode: SttMode) {
        busy = true
        activeMode = mode
        do {
            try backend.start(mode: mode)
            recordingStartedAt = Date()
            setState(.recording)
            busy = false
        } catch {
            busy = false
            recordingStartedAt = nil
            setState(.error)
            StatusStore.writeAppStatus(event: "record_start_failed", phase: "error", severity: "error", code: "record_start_failed", message: L("Aufnahme konnte nicht gestartet werden.", "Could not start recording."), detail: error.localizedDescription)
            AppLogger.log("record_start_failed \(error.localizedDescription)")
            if let problem = StatusStore.latestProblem(limit: 50) { onProblem?(problem) }
        }
    }

    private func stopRecording(mode: SttMode) {
        busy = true
        setState(.whisper)
        let generation = runGeneration
        backend.stop(mode: mode, onPhase: { [weak self] phase in
            DispatchQueue.main.async { self?.handlePhase(phase, generation: generation) }
        }) { [weak self] result in
            DispatchQueue.main.async { self?.handleResult(result, mode: mode, generation: generation) }
        }
    }

    /// Maps a backend pipeline phase to the high-level state that drives the
    /// icon and HUD (so the LLM/sparkles segment shows during cleanup).
    private func handlePhase(_ phase: TranscriptionPhase, generation: Int) {
        guard generation == runGeneration, busy else { return }
        let mapped: SttState = (phase == .postprocessing) ? .llm : .whisper
        if state != mapped { setState(mapped) }
    }

    /// Stops a live recording and transcribes what was captured. Used by the
    /// max-duration watchdog: hitting the limit must not destroy the audio.
    func stopAndTranscribe() {
        guard isRecording, !busy else { return }
        lastTriggerAt = Date()
        stopRecording(mode: activeMode)
    }

    func cancelRecording() {
        runGeneration += 1
        backend.cancel()
        recordingStartedAt = nil
        busy = false
        pendingStart = false
        setState(.idle)
        StatusStore.writeAppStatus(event: "recording_cancelled_by_app", phase: "idle", severity: "info", message: L("Aufnahme abgebrochen.", "Recording cancelled."))
        AppLogger.log("recording_cancelled")
    }

    func watchdog(maxDuration: TimeInterval) -> WatchdogReport {
        let duration = recordingDuration
        let exceeded = isRecording && maxDuration > 0 && duration > maxDuration
        return WatchdogReport(isRecording: isRecording, duration: duration, stalePidRemoved: false, exceededLimit: exceeded)
    }

    /// Mirrors the high-level state for the HUD phase timeline.
    func currentPhase() -> SttState? {
        switch state {
        case .whisper: return .whisper
        case .llm: return .llm
        case .error: return .error
        case .recording: return .recording
        default: return nil
        }
    }

    private func handleResult(_ result: Result<String, Error>, mode: SttMode, generation: Int) {
        guard generation == runGeneration else {
            AppLogger.log("stale_result_dropped generation=\(generation) current=\(runGeneration)")
            return
        }
        recordingStartedAt = nil
        switch result {
        case .success(let text) where !text.isEmpty:
            // Paste runs asynchronously (it may wait for a still-held hotkey
            // chord to clear). Stay busy across that wait so a press meanwhile
            // is queued as a fresh start rather than raced into a new recording.
            NativePaste.copyAndPaste(text) { [weak self] paste in
                self?.finishPaste(text: text, mode: mode, paste: paste, generation: generation)
            }
        case .success:
            // Stop produced no transcript (nothing was recording). Settle quietly.
            busy = false
            setState(.idle)
            settleAfterResult()
        case .failure(let error):
            busy = false
            setState(.error)
            StatusStore.writeAppStatus(event: "transcription_failed", phase: "error", severity: "error", code: "transcription_failed", message: error.localizedDescription)
            settleAfterResult()
        }
    }

    private func finishPaste(text: String, mode: SttMode, paste: NativePasteResult, generation: Int) {
        // The user cancelled (or a newer run started) while paste was waiting.
        guard generation == runGeneration else {
            AppLogger.log("stale_paste_dropped generation=\(generation) current=\(runGeneration)")
            return
        }
        busy = false
        switch paste {
        case .pasted:
            StatusStore.writeAppStatus(event: "native_paste_done", phase: "done", severity: "info", message: L("Transkript nativ eingefügt.", "Transcript pasted natively."), detail: "chars=\(text.count)")
            setState(.idle)
        case .clipboardOnly(let reason):
            StatusStore.writeAppStatus(event: "paste_failed_clipboard_ok", phase: "done", severity: "warning", code: "paste_permission_missing", message: L("Text liegt in der Zwischenablage.", "Text is on the clipboard."), detail: reason)
            setState(.error)
        }
        onTranscript?(text, mode, paste)
        if AppSettings.shared.sensitiveMode {
            // The raw voice recording is the more sensitive artifact; the
            // native pipeline leaves it in place until the next run.
            try? FileManager.default.removeItem(at: RuntimePaths.resultFile)
            try? FileManager.default.removeItem(at: RuntimePaths.recordingFile)
        }
        settleAfterResult()
    }

    /// Common tail after a run settles: surface any problem, log, and honor a
    /// press that arrived while we were busy.
    private func settleAfterResult() {
        if let problem = StatusStore.latestProblem(limit: 50) { onProblem?(problem) }
        AppLogger.log("transcription_finished state=\(state)")

        // A press arrived while we were busy: start a fresh recording now,
        // unless one already came alive (e.g. a double-tap during start).
        if pendingStart {
            pendingStart = false
            if !isRecording {
                lastTriggerAt = Date()
                startRecording(mode: pendingMode)
            }
        }
    }

    private func setState(_ newState: SttState) {
        state = newState
        onState?(newState)
    }
}
