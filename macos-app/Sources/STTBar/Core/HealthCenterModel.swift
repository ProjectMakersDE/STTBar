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
        next.append(item(L("Mikrofon", "Microphone"), Permissions.microphoneStatus == .authorized, L("Berechtigung", "Permission")))
        next.append(item(L("Bedienungshilfen", "Accessibility"), Permissions.accessibilityTrusted, L("Paste-Berechtigung", "Paste permission")))
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

    private func urlCheck(title: String, urlString: String, required: Bool) -> HealthCheckItem {
        guard let url = URL(string: urlString), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            return HealthCheckItem(title: title, detail: L("Ungültige URL", "Invalid URL"), level: required ? .error : .warning)
        }
        return HealthCheckItem(title: title, detail: url.absoluteString, level: .unknown)
    }

    private func testURL(_ url: String, label: String) {
        guard let u = URL(string: url), let scheme = u.scheme, ["http", "https"].contains(scheme) else {
            actionMessage = "\(label): \(L("ungültige URL", "invalid URL"))"
            return
        }
        var req = URLRequest(url: u)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                let code = (response as? HTTPURLResponse)?.statusCode
                let ok = error == nil && (code.map { (200..<500).contains($0) } ?? false)
                let detail = code.map { "HTTP \($0)" } ?? (error?.localizedDescription ?? L("nicht erreichbar", "unreachable"))
                self.actionMessage = "\(label): \(ok ? detail : L("nicht erreichbar", "unreachable"))"
                self.refresh()
            }
        }.resume()
    }
}
