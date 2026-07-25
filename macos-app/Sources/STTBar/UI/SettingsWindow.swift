import AppKit
import SwiftUI

/// Hosts `SettingsView` in a native titled window.
final class SettingsWindow {
    private var window: NSWindow?
    private let model: SettingsModel
    private let dataFolders: DataFolderModel
    private var editor: PromptEditorWindow?

    init(model: SettingsModel, isIdle: @escaping () -> Bool) {
        self.model = model
        self.dataFolders = DataFolderModel(isIdle: isIdle)
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model,
                                                                  dataFolders: dataFolders,
                                                                  openEditor: { [weak self] id in
                self?.openEditor(id)
            }))
            let w = NSWindow(contentViewController: host)
            w.title = L("STTBar – Einstellungen", "STTBar – Settings")
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 780, height: 620))
            window = w
        }
        // The window is reused, so re-read sizes and the busy flag on every open.
        dataFolders.refresh()
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
