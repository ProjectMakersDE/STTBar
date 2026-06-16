import AppKit
import SwiftUI

/// A separate titled window for editing one prompt. Can be opened standalone
/// (menu "Prompt bearbeiten…" → active prompt) or from the settings window.
final class PromptEditorWindow {
    private var window: NSWindow?
    private let model: SettingsModel
    private let promptId: String?

    /// Standalone init used by the menu — targets the active prompt.
    init(installDir: URL) {
        self.model = SettingsModel(installDir: installDir)
        self.promptId = nil
    }

    /// Init used from the settings window — shares its model.
    init(model: SettingsModel, promptId: String) {
        self.model = model
        self.promptId = promptId
    }

    func show() {
        let id = promptId ?? model.prompts.activePrompt?.id ?? ""
        let title = model.prompts.prompts.first { $0.id == id }?.title ?? "Prompt"
        if window == nil {
            let host = NSHostingController(rootView: PromptEditorView(model: model, promptId: id))
            let w = NSWindow(contentViewController: host)
            w.title = "Prompt bearbeiten – \(title)"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.setContentSize(NSSize(width: 600, height: 480))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
