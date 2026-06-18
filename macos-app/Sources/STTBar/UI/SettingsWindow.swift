import AppKit
import SwiftUI

/// Hosts `SettingsView` in a native titled window.
final class SettingsWindow {
    private var window: NSWindow?
    private let model: SettingsModel
    private var editor: PromptEditorWindow?

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model, openEditor: { [weak self] id in
                self?.openEditor(id)
            }))
            let w = NSWindow(contentViewController: host)
            w.title = "STTBar – Einstellungen"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 780, height: 620))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func openEditor(_ id: String) {
        let e = PromptEditorWindow(model: model, promptId: id)
        e.show()
        editor = e
    }
}
