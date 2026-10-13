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
    var onOpenDataFolder: ((DataLocation) -> Void)?
    var onSetLanguage: ((AppLanguage) -> Void)?

    private var state: SttState = .idle
    private var lastProblem: SttStatus?
    private var hasLastTranscript = false
    private var lastRunSummary = ""
    private var localModel: LocalModelStatus.State = .idle

    init() { setState(.idle); buildMenu() }

    func setState(_ state: SttState) {
        self.state = state
        let name: String
        switch state {
        case .idle: name = localModelLoading ? "hourglass" : "mic"
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

    /// Shows the local model load in the icon and menu, so a first launch does
    /// not look idle while the model downloads and warms up.
    func setLocalModelStatus(_ status: LocalModelStatus.State) {
        localModel = status
        setState(state)
    }

    private var localModelLoading: Bool {
        if case .loading = localModel { return true } else { return false }
    }

    private var localModelLine: String? {
        switch localModel {
        case .loading: return L("Lade lokales Modell… (beim ersten Mal 1 bis 5 Minuten)", "Loading local model… (1 to 5 minutes the first time)")
        case .failed(let model, _): return L("Lokales Modell nicht geladen: ", "Local model not loaded: ") + LocalModels.label(model)
        case .idle, .ready: return nil
        }
    }

    /// Rebuild the menu + tooltip (e.g. after a language change).
    func rebuild() {
        item.button?.toolTip = tooltip
        buildMenu()
    }

    private var tooltip: String {
        let stateText: String
        switch state {
        case .idle: stateText = localModelLine ?? L("Bereit", "Ready")
        case .recording: stateText = L("Aufnahme", "Recording")
        case .whisper: stateText = "Whisper"
        case .llm: stateText = "LLM"
        case .error: stateText = L("Fehler", "Error")
        }
        return ["STTBar", stateText, lastRunSummary].filter { !$0.isEmpty }.joined(separator: " - ")
    }

    private func buildMenu() {
        let menu = NSMenu()
        // Manual enabling: with auto-enablement, NSMenu re-enables every item
        // whose target responds, silently overriding the isEnabled flags below.
        menu.autoenablesItems = false
        if let line = localModelLine {
            let info = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
        }
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
        // One folder per entry: the old single item revealed files from two
        // different directories, which made Finder open two windows.
        let files = NSMenuItem(title: L("Dateien", "Files"), action: nil, keyEquivalent: "")
        let filesMenu = NSMenu()
        for location in DataLocation.allCases {
            let fi = NSMenuItem(title: location.title, action: #selector(openDataFolder(_:)), keyEquivalent: "")
            fi.target = self
            fi.representedObject = location.rawValue
            filesMenu.addItem(fi)
        }
        files.submenu = filesMenu
        menu.addItem(files)
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
    @objc private func openDataFolder(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let location = DataLocation(rawValue: raw) {
            onOpenDataFolder?(location)
        }
    }
    @objc private func selectLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let lang = AppLanguage(rawValue: raw) {
            onSetLanguage?(lang)
        }
    }
}
