import AppKit

/// Owns the menu-bar status item: a state-driven SF Symbol and a dropdown menu.
final class MenuBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onTrigger: ((SttMode) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onEditPrompt: (() -> Void)?

    init() { setState(.idle); buildMenu() }

    func setState(_ state: SttState) {
        let name: String
        switch state {
        case .idle: name = "mic"
        case .recording: name = "mic.fill"
        case .whisper: name = "waveform"
        case .llm: name = "sparkles"
        case .error: name = "exclamationmark.triangle"
        }
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "STT")
    }

    private func buildMenu() {
        let menu = NSMenu()
        for mode in SttMode.allCases {
            let mi = NSMenuItem(title: "Aufnahme: \(mode.label)", action: #selector(triggerMode(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = mode.rawValue; menu.addItem(mi)
        }
        menu.addItem(.separator())
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
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func editPrompt() { onEditPrompt?() }
}
