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
        next.append(item("STTBar", true, "App läuft"))
        next.append(launchAgentCheck())
        next.append(scriptCheck())
        next.append(toolCheck(["sox", "rec", "curl", "jq"]))
        next.append(item("Mikrofon", Permissions.microphoneStatus == .authorized, "Berechtigung"))
        next.append(item("Bedienungshilfen", Permissions.accessibilityTrusted, "Paste-Berechtigung"))
        next.append(HealthCheckItem(title: "Automation/System Events", detail: "Bei nativer Paste nicht erforderlich; Fallback kann sie nutzen.", level: .unknown))
        next.append(urlCheck(title: "Whisper-URL", urlString: settings.whisperURL, required: true))
        if settings.postprocessEnabled {
            next.append(urlCheck(title: "LM-Studio-URL", urlString: settings.lmStudioURL, required: true))
        } else {
            next.append(HealthCheckItem(title: "LM Studio", detail: "Postprocessing deaktiviert", level: .ok))
        }
        next.append(item("Whisper-Modell", !settings.whisperModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, settings.whisperModel))
        next.append(item("LLM-Modell", !settings.postprocessEnabled || !settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, settings.postprocessEnabled ? settings.llmModel : "deaktiviert"))
        next.append(item("Aktiver Prompt", FileManager.default.isReadableFile(atPath: settings.prompts.activeFileURL.path), settings.prompts.activeFileURL.path))
        next.append(item("Wörterbuch", FileManager.default.isReadableFile(atPath: settings.replacements.url.path), settings.replacements.url.path))
        let watch = runner.watchdog(maxDuration: TimeInterval(AppSettings.shared.maxRecordingSeconds))
        if watch.stalePidRemoved {
            next.append(HealthCheckItem(title: "Stale-Aufnahme", detail: "Veraltete PID wurde entfernt", level: .warning))
        } else if watch.isRecording {
            next.append(HealthCheckItem(title: "Aufnahme", detail: "\(Int(watch.duration))s läuft", level: watch.exceededLimit ? .warning : .ok))
        } else {
            next.append(HealthCheckItem(title: "Aufnahme", detail: "Keine hängende Aufnahme", level: .ok))
        }
        checks = next
    }

    func copyReport() {
        refresh()
        let report = diagnosticReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        actionMessage = "Diagnosebericht kopiert"
    }

    func testWhisper() { testURL(settings.whisperURL, label: "Whisper") }
    func testLMStudio() { testURL(settings.lmStudioURL, label: "LM Studio") }

    func microphoneTest() {
        Permissions.requestMicrophone()
        actionMessage = "Mikrofonstatus: \(Permissions.microphoneStatus.rawValue)"
        refresh()
    }

    func clipboardTest() {
        let result = NativePaste.copyAndPaste("STTBar Test")
        switch result {
        case .pasted: actionMessage = "Testtext eingefügt"
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
                self.actionMessage = result.success ? "Testaufnahme erstellt" : "Testaufnahme fehlgeschlagen: \(result.output)"
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
        let plist = LaunchAgent.plistURL
        guard FileManager.default.fileExists(atPath: plist.path) else {
            return HealthCheckItem(title: "LaunchAgent", detail: "Nicht installiert", level: .warning)
        }
        let text = (try? String(contentsOf: plist, encoding: .utf8)) ?? ""
        let ok = text.contains(settings.installDir.path)
        return HealthCheckItem(title: "LaunchAgent", detail: ok ? "Pfad korrekt" : "Pfad prüfen", level: ok ? .ok : .warning)
    }

    private func scriptCheck() -> HealthCheckItem {
        let scripts = ["stt-global.sh", "stt-record.sh", "stt-transcribe.sh", "stt-postprocess.sh", "stt-runtime.sh"]
        let missing = scripts.filter { !FileManager.default.isExecutableFile(atPath: settings.installDir.appendingPathComponent($0).path) }
        return HealthCheckItem(title: "Scripts", detail: missing.isEmpty ? "Vorhanden und ausführbar" : "Fehlt/nicht ausführbar: \(missing.joined(separator: ", "))", level: missing.isEmpty ? .ok : .error)
    }

    private func toolCheck(_ tools: [String]) -> HealthCheckItem {
        let missing = tools.filter { !Self.run("command -v \($0) >/dev/null 2>&1").success }
        return HealthCheckItem(title: "CLI-Tools", detail: missing.isEmpty ? tools.joined(separator: ", ") : "Fehlt: \(missing.joined(separator: ", "))", level: missing.isEmpty ? .ok : .error)
    }

    private func urlCheck(title: String, urlString: String, required: Bool) -> HealthCheckItem {
        guard let url = URL(string: urlString), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            return HealthCheckItem(title: title, detail: "Ungültige URL", level: required ? .error : .warning)
        }
        return HealthCheckItem(title: title, detail: url.absoluteString, level: .unknown)
    }

    private func testURL(_ url: String, label: String) {
        DispatchQueue.global().async {
            let result = Self.run("curl -sS --max-time 3 -o /dev/null -w '%{http_code}' \(Self.shellQuote(url))")
            DispatchQueue.main.async {
                self.actionMessage = "\(label): \(result.success ? result.output : "nicht erreichbar")"
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
