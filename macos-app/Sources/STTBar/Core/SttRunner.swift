import Foundation

/// High-level state reported to the icon + HUD.
enum SttState { case idle, recording, whisper, llm, error }

/// Drives the shell STT pipeline. First trigger starts recording; second stops
/// and transcribes. `onState` reports the high-level state for icon + HUD.
final class SttRunner {
    private let scriptPath: String
    private let phaseFile = "/tmp/stt-overlay-phase"
    private let pidFile = "/tmp/stt-recording.pid"
    let phaseFilePath: String
    var onState: ((SttState) -> Void)?
    private var task: Process?
    private var busy = false

    init(scriptPath: String) { self.scriptPath = scriptPath; self.phaseFilePath = phaseFile }

    var isRecording: Bool {
        guard let pid = try? String(contentsOfFile: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), let p = Int32(pid) else { return false }
        return kill(p, 0) == 0
    }

    func trigger(mode: SttMode) {
        if busy { onState?(isRecording ? .recording : .whisper); return }
        let wasRecording = isRecording
        try? FileManager.default.removeItem(atPath: phaseFile)
        busy = true
        onState?(wasRecording ? .whisper : .recording)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", "exec \(shellQuote(scriptPath))"]
        var env = ProcessInfo.processInfo.environment
        env["STT_MODE"] = mode.rawValue
        env["STT_NOTIFICATIONS"] = "0"
        env["STT_PHASE_FILE"] = phaseFile
        p.environment = env
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false; self.task = nil
                if wasRecording {
                    try? FileManager.default.removeItem(atPath: self.phaseFile)
                    self.onState?(proc.terminationStatus == 0 ? .idle : .error)
                } else {
                    self.onState?(self.isRecording ? .recording : .error)
                }
            }
        }
        do { try p.run(); task = p } catch { busy = false; onState?(.error) }
    }

    /// Reads the phase file the shell pipeline writes (whisper|llm|done|error).
    func currentPhase() -> SttState? {
        guard let v = try? String(contentsOfFile: phaseFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        switch v {
        case "whisper": return .whisper
        case "llm": return .llm
        case "error": return .error
        case "recording": return .recording
        default: return nil
        }
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
