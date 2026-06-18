import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menu: MenuBarController!
    private var hotkeys: HotkeyManager!
    private var runner: SttRunner!
    private var hud: HudOverlay!
    private var settingsWindow: SettingsWindow?
    private var promptWindow: PromptEditorWindow?
    private var statusWindow: StatusWindow?
    private var healthModel: HealthCenterModel?
    private var model: SettingsModel!
    private var warmer: ServerWarmer?
    private var watchdogTimer: Timer?
    private let history = TranscriptHistoryStore()
    private var lastTranscript: String?
    let installDir = InstallPaths.resolve()

    func applicationDidFinishLaunching(_ notification: Notification) {
        RuntimePaths.ensureDirectory()
        runner = SttRunner(scriptPath: installDir.appendingPathComponent("stt-global.sh").path)
        hud = HudOverlay(runner: runner)
        menu = MenuBarController()
        hotkeys = HotkeyManager()
        model = SettingsModel(installDir: installDir)
        warmer = ServerWarmer(model: model)
        warmer?.reload()
        healthModel = HealthCenterModel(settings: model, runner: runner)
        model.onHotkeysChanged = { [weak self] in
            self?.hotkeys.reload()
            self?.warmer?.reload()
        }

        runner.onState = { [weak self] state in
            self?.menu.setState(state)
            self?.hud.update(state)
        }
        runner.onProblem = { [weak self] problem in self?.menu.setLastProblem(problem) }
        runner.onTranscript = { [weak self] text, mode, paste in
            self?.lastTranscript = text
            self?.menu.setLastTranscriptAvailable(true)
            self?.history.add(text: text, mode: mode)
            self?.updateLastRunSummary()
            switch paste {
            case .pasted: AppLogger.log("native_paste ok chars=\(text.count)")
            case .clipboardOnly(let reason): AppLogger.log("native_paste clipboard_only reason=\(reason)")
            }
        }
        let trigger: (SttMode) -> Void = { [weak self] mode in self?.runner.trigger(mode: mode) }
        menu.onTrigger = trigger
        menu.onCancelRecording = { [weak self] in self?.runner.cancelRecording() }
        menu.onOpenStatus = { [weak self] in self?.showStatus() }
        menu.onOpenSettings = { [weak self] in self?.showSettings() }
        menu.onEditPrompt = { [weak self] in self?.showPromptEditor() }
        menu.onShowLastError = { [weak self] in self?.showLastError() }
        menu.onCopyLastTranscript = { [weak self] in self?.copyLastTranscript() }
        menu.onReinsertLastTranscript = { [weak self] in self?.reinsertLastTranscript() }
        menu.onOpenLogs = { Self.openLogs() }
        hotkeys.onTrigger = trigger
        hotkeys.onStatusesChanged = { [weak self] statuses in self?.model.syncHotkeyStatuses(statuses) }
        hotkeys.install()
        menu.setLastProblem(StatusStore.latestProblem())
        startWatchdog()
        AppLogger.log("app_started installDir=\(installDir.path)")
    }

    private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(model: model) }
        settingsWindow?.show()
    }

    private func showPromptEditor() {
        if promptWindow == nil { promptWindow = PromptEditorWindow(model: model, promptId: nil) }
        promptWindow?.show()
    }

    private func showStatus() {
        if let healthModel, statusWindow == nil { statusWindow = StatusWindow(model: healthModel) }
        statusWindow?.show()
    }

    private func showLastError() {
        guard let problem = StatusStore.latestProblem() else { return }
        let alert = NSAlert()
        alert.messageText = problem.message
        alert.informativeText = [problem.event, problem.code ?? "", problem.detail ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
        alert.alertStyle = problem.severity == "error" ? .critical : .warning
        alert.runModal()
    }

    private func copyLastTranscript() {
        guard let lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }

    private func reinsertLastTranscript() {
        guard let lastTranscript else { return }
        let result = NativePaste.copyAndPaste(lastTranscript)
        if case .clipboardOnly(let reason) = result {
            StatusStore.writeAppStatus(event: "last_transcript_clipboard_only", phase: "done", severity: "warning", code: "paste_permission_missing", message: "Letztes Transkript liegt in der Zwischenablage.", detail: reason)
            menu.setLastProblem(StatusStore.latestProblem())
        }
    }

    private static func openLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([AppLogger.logURL, RuntimePaths.eventsFile, RuntimePaths.metricsFile].filter {
            FileManager.default.fileExists(atPath: $0.path)
        })
    }

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let report = self.runner.watchdog(maxDuration: TimeInterval(AppSettings.shared.maxRecordingSeconds))
            if report.isRecording && self.runner.state == .idle {
                self.menu.setState(.recording)
                self.hud.update(.recording)
            }
            if report.exceededLimit {
                self.runner.cancelRecording()
                StatusStore.writeAppStatus(event: "recording_max_duration_cancelled", phase: "idle", severity: "warning", code: "recording_max_duration", message: "Aufnahme wegen Maximaldauer abgebrochen.")
            }
            if report.stalePidRemoved || report.exceededLimit {
                self.menu.setLastProblem(StatusStore.latestProblem())
            }
            self.healthModel?.refresh()
        }
    }

    private func updateLastRunSummary() {
        guard let metric = StatusStore.readMetrics(limit: 1).first else { return }
        let whisper = Double(metric.whisperMs ?? 0) / 1000
        let llm = Double(metric.postprocessMs ?? 0) / 1000
        menu.setLastRunSummary("Letzter Lauf: \(String(format: "%.1f", whisper))s Whisper, \(String(format: "%.1f", llm))s LLM")
    }
}

/// Resolves the directory containing the shell scripts + .env. Order: env var,
/// the standard install dir, else a sensible default.
enum InstallPaths {
    static func resolve() -> URL {
        if let p = ProcessInfo.processInfo.environment["STT_INSTALL_DIR"] { return URL(fileURLWithPath: p) }
        let std = (NSHomeDirectory() as NSString).appendingPathComponent(".local/share/stt")
        return URL(fileURLWithPath: std)
    }
}
