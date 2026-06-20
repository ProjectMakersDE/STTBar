import Foundation

/// High-level state reported to the icon + HUD.
enum SttState { case idle, recording, whisper, llm, error }

struct WatchdogReport {
    var isRecording: Bool
    var duration: TimeInterval
    var stalePidRemoved: Bool
    var exceededLimit: Bool
}

/// Drives the shell STT pipeline. First trigger starts recording; second stops
/// and transcribes. `onState` reports the high-level state for icon + HUD.
final class SttRunner {
    private let scriptPath: String
    let phaseFilePath: String
    var onState: ((SttState) -> Void)?
    var onTranscript: ((String, SttMode, NativePasteResult) -> Void)?
    var onProblem: ((SttStatus) -> Void)?
    private var task: Process?
    private var busy = false
    private(set) var state: SttState = .idle

    /// Single source of truth for the start/stop decision. Replaces the old
    /// implicit toggle that re-derived start-vs-stop independently in Swift and
    /// in the shell (which could diverge and mis-fire).
    private let toggle = RecordingToggle()
    private var lastTriggerAt: Date?
    /// A press that arrived while a previous run was still finishing. Honored as
    /// a fresh start once that run completes, so a press is never silently lost.
    private var pendingStart = false
    private var pendingMode: SttMode = .full

    init(scriptPath: String) {
        self.scriptPath = scriptPath
        RuntimePaths.ensureDirectory()
        self.phaseFilePath = RuntimePaths.phaseFile.path
    }

    var isRecording: Bool {
        pidIsAlive(RuntimePaths.pidFile) || pidIsAlive(RuntimePaths.legacyPidFile)
    }

    var recordingDuration: TimeInterval {
        guard let raw = try? String(contentsOf: RuntimePaths.recordingStartedFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let startMs = Double(raw) else { return 0 }
        return max(0, (Date().timeIntervalSince1970 * 1000 - startMs) / 1000)
    }

    func trigger(mode: SttMode) {
        let now = Date()
        let action = toggle.decide(isLiveRecording: isRecording, isBusy: busy, lastTriggerAt: lastTriggerAt, now: now)
        AppLogger.log("trigger mode=\(mode.rawValue) decided=\(action) isRecording=\(isRecording) busy=\(busy)")
        if action == .ignore { return }
        lastTriggerAt = now
        switch action {
        case .queueStart:
            // A run is still finishing (no live audio). The user's rule: this
            // press is a start. Remember it and fire once the run completes.
            pendingStart = true
            pendingMode = mode
        case .start:
            launch(.start, mode: mode)
        case .stop:
            launch(.stop, mode: mode)
        case .ignore:
            break
        }
    }

    /// Spawns the shell pipeline for an explicit `start` or `stop`. The action
    /// is passed to the shell via `STT_ACTION` so the shell no longer re-derives
    /// it from the pid file (which could disagree with what Swift decided).
    private func launch(_ action: SttToggleAction, mode: SttMode) {
        try? FileManager.default.removeItem(at: RuntimePaths.phaseFile)
        try? FileManager.default.removeItem(at: RuntimePaths.resultFile)
        busy = true
        setState(action == .stop ? .whisper : .recording)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", "exec \(shellQuote(scriptPath))"]
        p.environment = runnerEnvironment(mode: mode, action: action)
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.handleTermination(proc, action: action, mode: mode)
            }
        }
        do {
            try p.run()
            task = p
        } catch {
            busy = false
            setState(.error)
            StatusStore.writeAppStatus(event: "runner_start_failed", phase: "error", severity: "error", code: "runner_start_failed", message: "STT-Script konnte nicht gestartet werden.", detail: error.localizedDescription)
            AppLogger.log("runner_start_failed \(error.localizedDescription)")
        }
    }

    func cancelRecording() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", "STT_RUNTIME_DIR=\(shellQuote(RuntimePaths.directory.path)) exec \(shellQuote(scriptDirectory.appendingPathComponent("stt-record.sh").path)) cancel"]
        do {
            try p.run()
            p.waitUntilExit()
            task?.terminate()
            task = nil
            busy = false
            pendingStart = false
            setState(.idle)
            StatusStore.writeAppStatus(event: "recording_cancelled_by_app", phase: "idle", severity: "info", message: "Aufnahme abgebrochen.")
            AppLogger.log("recording_cancelled")
        } catch {
            setState(.error)
            StatusStore.writeAppStatus(event: "recording_cancel_failed", phase: "error", severity: "error", code: "recording_cancel_failed", message: "Aufnahme konnte nicht abgebrochen werden.", detail: error.localizedDescription)
        }
    }

    func watchdog(maxDuration: TimeInterval) -> WatchdogReport {
        var staleRemoved = false
        if FileManager.default.fileExists(atPath: RuntimePaths.pidFile.path), !isRecording {
            try? FileManager.default.removeItem(at: RuntimePaths.pidFile)
            try? FileManager.default.removeItem(at: RuntimePaths.lockFile)
            staleRemoved = true
            StatusStore.writeAppStatus(event: "stale_pid_removed", phase: "idle", severity: "warning", code: "stale_pid_removed", message: "Veraltete Aufnahme-Markierung entfernt.")
            AppLogger.log("stale_pid_removed")
        }
        if FileManager.default.fileExists(atPath: RuntimePaths.legacyPidFile.path), !pidIsAlive(RuntimePaths.legacyPidFile) {
            try? FileManager.default.removeItem(at: RuntimePaths.legacyPidFile)
            staleRemoved = true
            StatusStore.writeAppStatus(event: "legacy_stale_pid_removed", phase: "idle", severity: "warning", code: "legacy_stale_pid_removed", message: "Alte /tmp-Aufnahme-Markierung entfernt.")
            AppLogger.log("legacy_stale_pid_removed")
        }
        let duration = recordingDuration
        let exceeded = isRecording && maxDuration > 0 && duration > maxDuration
        return WatchdogReport(isRecording: isRecording, duration: duration, stalePidRemoved: staleRemoved, exceededLimit: exceeded)
    }

    /// Reads the phase file the shell pipeline writes (whisper|llm|done|error).
    func currentPhase() -> SttState? {
        guard let v = try? String(contentsOf: RuntimePaths.phaseFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        switch v {
        case "whisper": return .whisper
        case "llm": return .llm
        case "error": return .error
        case "recording": return .recording
        default: return nil
        }
    }

    private var scriptDirectory: URL {
        URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
    }

    private func handleTermination(_ proc: Process, action: SttToggleAction, mode: SttMode) {
        busy = false
        task = nil
        if action == .stop {
            try? FileManager.default.removeItem(at: RuntimePaths.phaseFile)
            if proc.terminationStatus == 0, let text = try? String(contentsOf: RuntimePaths.resultFile, encoding: .utf8), !text.isEmpty {
                let paste = NativePaste.copyAndPaste(text)
                switch paste {
                case .pasted:
                    StatusStore.writeAppStatus(event: "native_paste_done", phase: "done", severity: "info", message: "Transkript nativ eingefügt.", detail: "chars=\(text.count)")
                    setState(.idle)
                case .clipboardOnly(let reason):
                    StatusStore.writeAppStatus(event: "paste_failed_clipboard_ok", phase: "done", severity: "warning", code: "paste_permission_missing", message: "Text liegt in der Zwischenablage.", detail: reason)
                    setState(.error)
                }
                onTranscript?(text, mode, paste)
                if AppSettings.shared.sensitiveMode {
                    try? FileManager.default.removeItem(at: RuntimePaths.resultFile)
                }
            } else if proc.terminationStatus == 0 {
                // Stop ran but produced no transcript — there was nothing
                // actually recording (stale state). Settle to idle quietly
                // instead of flashing an error.
                setState(.idle)
            } else {
                setState(.error)
                StatusStore.writeAppStatus(event: "result_missing", phase: "error", severity: "error", code: "result_missing", message: "Kein Transkript von der Shell erhalten.")
            }
        } else {
            setState(isRecording ? .recording : .error)
        }
        if let problem = StatusStore.latestProblem(limit: 50) {
            onProblem?(problem)
        }
        AppLogger.log("termination status=\(proc.terminationStatus) action=\(action) state=\(state)")

        // A press arrived while we were busy: start a fresh recording now,
        // unless one already came alive (e.g. a double-tap during start).
        if pendingStart {
            pendingStart = false
            if !isRecording {
                let queuedMode = pendingMode
                lastTriggerAt = Date()
                launch(.start, mode: queuedMode)
            }
        }
    }

    private func setState(_ newState: SttState) {
        state = newState
        onState?(newState)
    }

    private func pidIsAlive(_ url: URL) -> Bool {
        guard let pid = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), let p = Int32(pid) else { return false }
        return kill(p, 0) == 0
    }

    private func runnerEnvironment(mode: SttMode, action: SttToggleAction) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["STT_MODE"] = mode.rawValue
        env["STT_ACTION"] = action == .stop ? "stop" : "start"
        env["STT_NOTIFICATIONS"] = "0"
        env["STT_APP_NATIVE_PASTE"] = "1"
        env["STT_RUNTIME_DIR"] = RuntimePaths.directory.path
        env["STT_PHASE_FILE"] = RuntimePaths.phaseFile.path
        env["STT_STATUS_FILE"] = RuntimePaths.statusFile.path
        env["STT_EVENTS_FILE"] = RuntimePaths.eventsFile.path
        env["STT_METRICS_FILE"] = RuntimePaths.metricsFile.path
        env["STT_RESULT_FILE"] = RuntimePaths.resultFile.path
        return env
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
