import AppKit
import Foundation

struct HealthCheckItem: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var detail: String
    var level: Level

    enum Level: String {
        case ok, warning, error, unknown
    }
}

final class HealthCenterModel: ObservableObject {
    @Published var checks: [HealthCheckItem] = []
    @Published var metrics: [RunMetric] = []
    @Published var lastProblem: SttStatus?
    @Published var actionMessage: String?

    private let settings: SettingsModel
    private let runner: SttRunner

    init(settings: SettingsModel, runner: SttRunner) {
        self.settings = settings
        self.runner = runner
        refresh()
    }

    func refresh() {
        RuntimePaths.ensureDirectory()
        lastProblem = StatusStore.latestProblem()
        metrics = StatusStore.readMetrics(limit: 20)
        var next: [HealthCheckItem] = []
        next.append(item("STTBar", true, L("App läuft", "App running")))
        next.append(launchAgentCheck())
        next.append(scriptCheck())
        next.append(toolCheck(["sox", "rec", "curl", "jq"]))
        next.append(item(L("Mikrofon", "Microphone"), Permissions.microphoneStatus == .authorized, L("Berechtigung", "Permission")))
        next.append(item(L("Bedienungshilfen", "Accessibility"), Permissions.accessibilityTrusted, L("Paste-Berechtigung", "Paste permission")))
        next.append(HealthCheckItem(title: "Automation/System Events", detail: L("Bei nativer Paste nicht erforderlich; Fallback kann sie nutzen.", "Not required for native paste; the fallback may use it."), level: .unknown))
        next.append(urlCheck(title: L("Whisper-URL", "Whisper URL"), urlString: settings.whisperURL, required: true))
        if settings.postprocessEnabled {
            next.append(urlCheck(title: L("LM-Studio-URL", "LM Studio URL"), urlString: settings.lmStudioURL, required: true))
        } else {
            next.append(HealthCheckItem(title: "LM Studio", detail: L("Postprocessing deaktiviert", "Post-processing disabled"), level: .ok))
        }
        next.append(item(L("Whisper-Modell", "Whisper model"), !settings.whisperModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, settings.whisperModel))
        next.append(item(L("LLM-Modell", "LLM model"), !settings.postprocessEnabled || !settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, settings.postprocessEnabled ? settings.llmModel : L("deaktiviert", "disabled")))
        next.append(item(L("Aktiver Prompt", "Active prompt"), FileManager.default.isReadableFile(atPath: settings.prompts.activeFileURL.path), settings.prompts.activeFileURL.path))
        next.append(item(L("Wörterbuch", "Vocabulary"), FileManager.default.isReadableFile(atPath: settings.replacements.url.path), settings.replacements.url.path))
        let watch = runner.watchdog(maxDuration: TimeInterval(AppSettings.shared.maxRecordingSeconds))
        if watch.stalePidRemoved {
            next.append(HealthCheckItem(title: L("Stale-Aufnahme", "Stale recording"), detail: L("Veraltete PID wurde entfernt", "Stale PID removed"), level: .warning))
        } else if watch.isRecording {
            next.append(HealthCheckItem(title: L("Aufnahme", "Recording"), detail: "\(Int(watch.duration))s " + L("läuft", "running"), level: watch.exceededLimit ? .warning : .ok))
        } else {
            next.append(HealthCheckItem(title: L("Aufnahme", "Recording"), detail: L("Keine hängende Aufnahme", "No stuck recording"), level: .ok))
        }
        checks = next
    }

    func copyReport() {
        refresh()
        let report = diagnosticReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        actionMessage = L("Diagnosebericht kopiert", "Diagnostic report copied")
    }

    func testWhisper() { testURL(settings.whisperURL, label: "Whisper") }
    func testLMStudio() { testURL(settings.lmStudioURL, label: "LM Studio") }

    func microphoneTest() {
        Permissions.requestMicrophone()
        actionMessage = L("Mikrofonstatus: ", "Microphone status: ") + "\(Permissions.microphoneStatus.rawValue)"
        refresh()
    }

    func clipboardTest() {
        let result = NativePaste.copyAndPaste("STTBar Test")
        switch result {
        case .pasted: actionMessage = L("Testtext eingefügt", "Test text inserted")
        case .clipboardOnly(let reason): actionMessage = reason
        }
        refresh()
    }

    func testRecording() {
        DispatchQueue.global().async {
            let script = self.settings.installDir.appendingPathComponent("stt-record.sh").path
            _ = Self.run("STT_RUNTIME_DIR=\(Self.shellQuote(RuntimePaths.directory.path)) \(Self.shellQuote(script)) start >/dev/null 2>&1")
            Thread.sleep(forTimeInterval: 3)
            let result = Self.run("STT_RUNTIME_DIR=\(Self.shellQuote(RuntimePaths.directory.path)) \(Self.shellQuote(script)) stop 2>&1")
            DispatchQueue.main.async {
                self.actionMessage = result.success ? L("Testaufnahme erstellt", "Test recording created") : L("Testaufnahme fehlgeschlagen: ", "Test recording failed: ") + result.output
                self.refresh()
            }
        }
    }

    func prewarmServers() {
        testWhisper()
        if settings.postprocessEnabled { testLMStudio() }
    }

    private func diagnosticReport() -> String {
        let version = VersionInfo.load(installDir: settings.installDir)
        let rows = checks.map { "\($0.level.rawValue.uppercased())\t\($0.title)\t\($0.detail)" }.joined(separator: "\n")
        let problem = lastProblem.map { "\($0.severity) \($0.event): \($0.message) \($0.detail ?? "")" } ?? "none"
        return """
        STTBar Diagnose
        app_commit=\(version.appCommit)
        script_commit=\(version.scriptCommit)
        install_dir=\(settings.installDir.path)
        runtime_dir=\(RuntimePaths.directory.path)
        whisper_url=\(settings.whisperURL)
        whisper_model=\(settings.whisperModel)
        postprocess_enabled=\(settings.postprocessEnabled ? "1" : "0")
        provider=\(settings.provider)
        postprocess_model=\(settings.llmModel)
        last_problem=\(problem)

        \(rows)
        """
    }

    private func item(_ title: String, _ ok: Bool, _ detail: String) -> HealthCheckItem {
        HealthCheckItem(title: title, detail: detail, level: ok ? .ok : .error)
    }

    private func launchAgentCheck() -> HealthCheckItem {
        let enabled = LoginItem.isEnabled
        return HealthCheckItem(title: L("Autostart", "Launch at login"),
                               detail: enabled ? L("Aktiv", "Enabled") : L("Aus", "Off"),
                               level: .ok)
    }

    private func scriptCheck() -> HealthCheckItem {
        let scripts = ["stt-global.sh", "stt-record.sh", "stt-transcribe.sh", "stt-postprocess.sh", "stt-runtime.sh"]
        let missing = scripts.filter { !FileManager.default.isExecutableFile(atPath: settings.installDir.appendingPathComponent($0).path) }
        return HealthCheckItem(title: "Scripts", detail: missing.isEmpty ? L("Vorhanden und ausführbar", "Present and executable") : L("Fehlt/nicht ausführbar: ", "Missing/not executable: ") + missing.joined(separator: ", "), level: missing.isEmpty ? .ok : .error)
    }

    private func toolCheck(_ tools: [String]) -> HealthCheckItem {
        let missing = tools.filter { !Self.run("command -v \($0) >/dev/null 2>&1").success }
        return HealthCheckItem(title: "CLI-Tools", detail: missing.isEmpty ? tools.joined(separator: ", ") : L("Fehlt: ", "Missing: ") + missing.joined(separator: ", "), level: missing.isEmpty ? .ok : .error)
    }

    private func urlCheck(title: String, urlString: String, required: Bool) -> HealthCheckItem {
        guard let url = URL(string: urlString), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            return HealthCheckItem(title: title, detail: L("Ungültige URL", "Invalid URL"), level: required ? .error : .warning)
        }
        return HealthCheckItem(title: title, detail: url.absoluteString, level: .unknown)
    }

    private func testURL(_ url: String, label: String) {
        DispatchQueue.global().async {
            let result = Self.run("curl -sS --max-time 3 -o /dev/null -w '%{http_code}' \(Self.shellQuote(url))")
            DispatchQueue.main.async {
                self.actionMessage = "\(label): \(result.success ? result.output : L("nicht erreichbar", "unreachable"))"
                self.refresh()
            }
        }
    }

    private static func run(_ command: String) -> (success: Bool, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus == 0, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
