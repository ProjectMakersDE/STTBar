import AppKit

/// Owns the menu-bar status item: a state-driven SF Symbol and a dropdown menu.
final class MenuBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onTrigger: ((SttMode, Date?) -> Void)?
    var onCancelRecording: (() -> Void)?
    var onOpenStatus: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenOnboarding: (() -> Void)?
    var onEditPrompt: (() -> Void)?
    var onShowLastError: (() -> Void)?
    var onCopyLastTranscript: (() -> Void)?
    var onReinsertLastTranscript: (() -> Void)?
    var onOpenLogs: (() -> Void)?
    var onSetLanguage: ((AppLanguage) -> Void)?

    private var state: SttState = .idle
    private var lastProblem: SttStatus?
    private var hasLastTranscript = false
    private var lastRunSummary = ""

    init() { setState(.idle); buildMenu() }

    func setState(_ state: SttState) {
        self.state = state
        let name: String
        switch state {
        case .idle: name = "mic"
        case .recording: name = "mic.fill"
        case .whisper: name = "waveform"
        case .llm: name = "sparkles"
        case .error: name = "exclamationmark.triangle"
        }
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "STT")
        item.button?.toolTip = tooltip
        buildMenu()
    }

    func setLastProblem(_ problem: SttStatus?) {
        lastProblem = problem
        item.button?.toolTip = tooltip
        buildMenu()
    }

    func setLastTranscriptAvailable(_ available: Bool) {
        hasLastTranscript = available
        buildMenu()
    }

    func setLastRunSummary(_ summary: String) {
        lastRunSummary = summary
        item.button?.toolTip = tooltip
        buildMenu()
    }

    /// Rebuild the menu + tooltip (e.g. after a language change).
    func rebuild() {
        item.button?.toolTip = tooltip
        buildMenu()
    }

    private var tooltip: String {
        let stateText: String
        switch state {
        case .idle: stateText = L("Bereit", "Ready")
        case .recording: stateText = L("Aufnahme", "Recording")
        case .whisper: stateText = "Whisper"
        case .llm: stateText = "LLM"
        case .error: stateText = L("Fehler", "Error")
        }
        return ["STTBar", stateText, lastRunSummary].filter { !$0.isEmpty }.joined(separator: " - ")
    }

    private func buildMenu() {
        let menu = NSMenu()
        for mode in SttMode.allCases {
            let title = state == .recording
                ? "\(L("Stoppen", "Stop")): \(mode.label)"
                : "\(L("Aufnahme", "Record")): \(mode.label)"
            let mi = NSMenuItem(title: title, action: #selector(triggerMode(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = mode.rawValue; menu.addItem(mi)
        }
        let cancel = NSMenuItem(title: L("Aufnahme abbrechen", "Cancel recording"), action: #selector(cancelRecording), keyEquivalent: "")
        cancel.target = self; cancel.isEnabled = state == .recording
        menu.addItem(cancel)
        menu.addItem(.separator())
        let reinsert = NSMenuItem(title: L("Letztes Transkript erneut einfügen", "Re-insert last transcript"), action: #selector(reinsertLastTranscript), keyEquivalent: "")
        reinsert.target = self; reinsert.isEnabled = hasLastTranscript
        menu.addItem(reinsert)
        let copy = NSMenuItem(title: L("Letztes Transkript kopieren", "Copy last transcript"), action: #selector(copyLastTranscript), keyEquivalent: "")
        copy.target = self; copy.isEnabled = hasLastTranscript
        menu.addItem(copy)
        let error = NSMenuItem(title: L("Letzten Fehler anzeigen", "Show last error"), action: #selector(showLastError), keyEquivalent: "")
        error.target = self; error.isEnabled = lastProblem != nil
        menu.addItem(error)
        let logs = NSMenuItem(title: L("Logs öffnen", "Open logs"), action: #selector(openLogs), keyEquivalent: "")
        logs.target = self; menu.addItem(logs)
        menu.addItem(.separator())
        let status = NSMenuItem(title: L("Status & Diagnose…", "Status & diagnostics…"), action: #selector(openStatus), keyEquivalent: "")
        status.target = self; menu.addItem(status)
        let settings = NSMenuItem(title: L("Einstellungen…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        let onboarding = NSMenuItem(title: L("Einrichtung erneut starten…", "Run setup again…"), action: #selector(openOnboarding), keyEquivalent: "")
        onboarding.target = self; menu.addItem(onboarding)
        let edit = NSMenuItem(title: L("Prompt bearbeiten…", "Edit prompt…"), action: #selector(editPrompt), keyEquivalent: "")
        edit.target = self; menu.addItem(edit)
        menu.addItem(.separator())
        let langItem = NSMenuItem(title: L("Sprache", "Language"), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for lang in AppLanguage.allCases {
            let name = lang == .de ? "Deutsch" : "English"
            let li = NSMenuItem(title: name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            li.target = self
            li.representedObject = lang.rawValue
            li.state = (Localization.shared.language == lang) ? .on : .off
            langMenu.addItem(li)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("STTBar beenden", "Quit STTBar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc private func triggerMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = SttMode(rawValue: raw) { onTrigger?(m, nil) }
    }
    @objc private func cancelRecording() { onCancelRecording?() }
    @objc private func openStatus() { onOpenStatus?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openOnboarding() { onOpenOnboarding?() }
    @objc private func editPrompt() { onEditPrompt?() }
    @objc private func showLastError() { onShowLastError?() }
    @objc private func copyLastTranscript() { onCopyLastTranscript?() }
    @objc private func reinsertLastTranscript() { onReinsertLastTranscript?() }
    @objc private func openLogs() { onOpenLogs?() }
    @objc private func selectLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let lang = AppLanguage(rawValue: raw) {
            onSetLanguage?(lang)
        }
    }
}
