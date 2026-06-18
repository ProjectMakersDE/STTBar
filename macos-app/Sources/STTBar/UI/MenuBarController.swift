import AppKit

/// Owns the menu-bar status item: a state-driven SF Symbol and a dropdown menu.
final class MenuBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onTrigger: ((SttMode) -> Void)?
    var onCancelRecording: (() -> Void)?
    var onOpenStatus: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onEditPrompt: (() -> Void)?
    var onShowLastError: (() -> Void)?
    var onCopyLastTranscript: (() -> Void)?
    var onReinsertLastTranscript: (() -> Void)?
    var onOpenLogs: (() -> Void)?

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

    private var tooltip: String {
        let stateText: String
        switch state {
        case .idle: stateText = "Bereit"
        case .recording: stateText = "Aufnahme"
        case .whisper: stateText = "Whisper"
        case .llm: stateText = "LLM"
        case .error: stateText = "Fehler"
        }
        return ["STTBar", stateText, lastRunSummary].filter { !$0.isEmpty }.joined(separator: " - ")
    }

    private func buildMenu() {
        let menu = NSMenu()
        for mode in SttMode.allCases {
            let title = state == .recording ? "Stoppen: \(mode.label)" : "Aufnahme: \(mode.label)"
            let mi = NSMenuItem(title: title, action: #selector(triggerMode(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = mode.rawValue; menu.addItem(mi)
        }
        let cancel = NSMenuItem(title: "Aufnahme abbrechen", action: #selector(cancelRecording), keyEquivalent: "")
        cancel.target = self; cancel.isEnabled = state == .recording
        menu.addItem(cancel)
        menu.addItem(.separator())
        let reinsert = NSMenuItem(title: "Letztes Transkript erneut einfügen", action: #selector(reinsertLastTranscript), keyEquivalent: "")
        reinsert.target = self; reinsert.isEnabled = hasLastTranscript
        menu.addItem(reinsert)
        let copy = NSMenuItem(title: "Letztes Transkript kopieren", action: #selector(copyLastTranscript), keyEquivalent: "")
        copy.target = self; copy.isEnabled = hasLastTranscript
        menu.addItem(copy)
        let error = NSMenuItem(title: "Letzten Fehler anzeigen", action: #selector(showLastError), keyEquivalent: "")
        error.target = self; error.isEnabled = lastProblem != nil
        menu.addItem(error)
        let logs = NSMenuItem(title: "Logs öffnen", action: #selector(openLogs), keyEquivalent: "")
        logs.target = self; menu.addItem(logs)
        menu.addItem(.separator())
        let status = NSMenuItem(title: "Status & Diagnose…", action: #selector(openStatus), keyEquivalent: "")
        status.target = self; menu.addItem(status)
        let settings = NSMenuItem(title: "Einstellungen…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        let edit = NSMenuItem(title: "Prompt bearbeiten…", action: #selector(editPrompt), keyEquivalent: "")
        edit.target = self; menu.addItem(edit)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "STTBar beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc private func triggerMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = SttMode(rawValue: raw) { onTrigger?(m) }
    }
    @objc private func cancelRecording() { onCancelRecording?() }
    @objc private func openStatus() { onOpenStatus?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func editPrompt() { onEditPrompt?() }
    @objc private func showLastError() { onShowLastError?() }
    @objc private func copyLastTranscript() { onCopyLastTranscript?() }
    @objc private func reinsertLastTranscript() { onReinsertLastTranscript?() }
    @objc private func openLogs() { onOpenLogs?() }
}
