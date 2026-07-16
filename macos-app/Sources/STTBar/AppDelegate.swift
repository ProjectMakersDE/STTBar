import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()
    private var menu: MenuBarController!
    private var hotkeys: HotkeyManager!
    private var runner: SttRunner!
    private var hud: HudOverlay!
    private var settingsWindow: SettingsWindow?
    private var onboardingWindow: OnboardingWindow?
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
        // Single-instance guard: if another STTBar is already running (e.g. a
        // relaunch race during an in-app update), yield to it.
        let me = NSRunningApplication.current
        let dupes = NSRunningApplication.runningApplications(withBundleIdentifier: me.bundleIdentifier ?? "de.projectmakers.sttbar")
            .filter { $0.processIdentifier != me.processIdentifier }
        if !dupes.isEmpty {
            NSApp.terminate(nil)
            return
        }
        RuntimePaths.ensureDirectory()
        try? FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        // Model first: the native backend snapshots its settings at stop() time.
        model = SettingsModel(installDir: installDir)
        let settingsModel = model!
        let backend = NativeBackend(config: { TranscriptionConfig.from(settingsModel) })
        runner = SttRunner(backend: backend)
        hud = HudOverlay(runner: runner)
        menu = MenuBarController()
        hotkeys = HotkeyManager()
        warmer = ServerWarmer(model: model)
        warmer?.reload()
        healthModel = HealthCenterModel(settings: model, runner: runner)
        model.onHotkeysChanged = { [weak self] in
            self?.hotkeys.reload()
            self?.warmer?.reload()
        }
        model.onClearHistory = { [weak self] in
            self?.history.clear()
            self?.lastTranscript = nil
            self?.menu.setLastTranscriptAvailable(false)
        }

        runner.onState = { [weak self] state in
            self?.menu.setState(state)
            self?.hud.update(state)
            self?.onboardingWindow?.flow.liveState = state
        }
        runner.onProblem = { [weak self] problem in
            guard let self else { return }
            self.menu.setLastProblem(problem)
            // Self-heal: a hard failure on an unusable config means the user is
            // stuck (e.g. today's "Rot") — bring the setup wizard back.
            if problem.severity == "error", OnboardingReadiness.needsOnboarding(model: self.model) {
                self.showOnboarding()
            }
        }
        runner.onTranscript = { [weak self] text, mode, paste in
            self?.lastTranscript = text
            self?.onboardingWindow?.flow.lastTestTranscript = text
            self?.menu.setLastTranscriptAvailable(true)
            self?.history.add(text: text, mode: mode)
            self?.updateLastRunSummary()
            switch paste {
            case .pasted: AppLogger.log("native_paste ok chars=\(text.count)")
            case .clipboardOnly(let reason): AppLogger.log("native_paste clipboard_only reason=\(reason)")
            }
        }
        let trigger: (SttMode, Date?) -> Void = { [weak self] mode, eventTime in self?.runner.trigger(mode: mode, eventTime: eventTime) }
        menu.onTrigger = trigger
        menu.onCancelRecording = { [weak self] in self?.runner.cancelRecording() }
        menu.onOpenStatus = { [weak self] in self?.showStatus() }
        menu.onOpenSettings = { [weak self] in self?.showSettings() }
        menu.onOpenOnboarding = { [weak self] in self?.showOnboarding(force: true) }
        menu.onEditPrompt = { [weak self] in self?.showPromptEditor() }
        menu.onShowLastError = { [weak self] in self?.showLastError() }
        menu.onCopyLastTranscript = { [weak self] in self?.copyLastTranscript() }
        menu.onReinsertLastTranscript = { [weak self] in self?.reinsertLastTranscript() }
        menu.onOpenLogs = { Self.openLogs() }
        menu.onSetLanguage = { [weak self] lang in self?.model.setAppLanguage(lang) }
        Localization.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.menu.rebuild() }
            .store(in: &cancellables)
        hotkeys.onTrigger = trigger
        hotkeys.onStatusesChanged = { [weak self] statuses in self?.model.syncHotkeyStatuses(statuses) }
        hotkeys.install()
        Permissions.requestMicrophone()
        menu.setLastProblem(StatusStore.latestProblem())
        startWatchdog()
        AppLogger.log("app_started installDir=\(installDir.path)")
        // First run (no completion flag) or an unusable config opens the wizard.
        if OnboardingReadiness.needsOnboarding(model: model) { showOnboarding(force: true) }
    }

    private func showOnboarding(force: Bool = false) {
        if onboardingWindow == nil {
            let w = OnboardingWindow(model: model)
            w.onStartRawTest = { [weak self] in self?.runner.trigger(mode: .raw, eventTime: nil) }
            w.onCompleted = { [weak self] in self?.menu.rebuild() }
            onboardingWindow = w
            // Steer a fresh, unconfigured user to local without clobbering a real
            // remote config. Only on first creation, so it never yanks an
            // in-progress selection.
            if !OnboardingReadiness.isCompleted {
                model.transcriptionSource = OnboardingReadiness.preferredInitialSource(model: model)
            }
        }
        onboardingWindow?.show(reset: force)
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
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let report = self.runner.watchdog(maxDuration: TimeInterval(AppSettings.shared.maxRecordingSeconds))
            if report.isRecording && self.runner.state == .idle {
                self.menu.setState(.recording)
                self.hud.update(.recording)
            }
            if report.exceededLimit {
                // Stop and transcribe: hitting the limit must not throw away
                // everything the user just said.
                self.runner.stopAndTranscribe()
                StatusStore.writeAppStatus(event: "recording_max_duration_stopped", phase: "whisper", severity: "warning", code: "recording_max_duration", message: L("Maximale Aufnahmedauer erreicht - Aufnahme wird transkribiert.", "Max recording duration reached - transcribing what was captured."))
            }
            if report.stalePidRemoved || report.exceededLimit {
                self.menu.setLastProblem(StatusStore.latestProblem())
            }
            self.healthModel?.refresh()
        }
        // .common keeps the watchdog ticking while a menu or modal is open.
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func updateLastRunSummary() {
        guard let metric = StatusStore.readMetrics(limit: 1).first else { return }
        let whisper = Double(metric.whisperMs ?? 0) / 1000
        let llm = Double(metric.postprocessMs ?? 0) / 1000
        menu.setLastRunSummary("Letzter Lauf: \(String(format: "%.1f", whisper))s Whisper, \(String(format: "%.1f", llm))s LLM")
    }
}

/// Resolves the directory holding the app's config (.env, prompts, profiles,
/// replacements). Under the App Sandbox this is the container's Application
/// Support; `STT_INSTALL_DIR` overrides it for tests/dev.
enum InstallPaths {
    static func resolve() -> URL {
        if let p = ProcessInfo.processInfo.environment["STT_INSTALL_DIR"], !p.isEmpty {
            return URL(fileURLWithPath: p)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("STTBar", isDirectory: true)
    }
}
