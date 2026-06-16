import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menu: MenuBarController!
    private var hotkeys: HotkeyManager!
    private var runner: SttRunner!
    private var hud: HudOverlay!
    private var settingsWindow: SettingsWindow?
    private var promptWindow: PromptEditorWindow?
    private var model: SettingsModel!
    let installDir = InstallPaths.resolve()

    func applicationDidFinishLaunching(_ notification: Notification) {
        runner = SttRunner(scriptPath: installDir.appendingPathComponent("stt-global.sh").path)
        hud = HudOverlay(runner: runner)
        menu = MenuBarController()
        hotkeys = HotkeyManager()
        // Build the shared settings model up front: this seeds prompts.json +
        // the default prompt and wires STT_POSTPROCESS_PROMPT_FILE into .env so
        // prompt switching works even before the settings window is opened.
        model = SettingsModel(installDir: installDir)
        model.onHotkeysChanged = { [weak self] in self?.hotkeys.reload() }

        runner.onState = { [weak self] state in
            self?.menu.setState(state)
            self?.hud.update(state)
        }
        let trigger: (SttMode) -> Void = { [weak self] mode in self?.runner.trigger(mode: mode) }
        menu.onTrigger = trigger
        hotkeys.onTrigger = trigger
        menu.onOpenSettings = { [weak self] in self?.showSettings() }
        menu.onEditPrompt = { [weak self] in self?.showPromptEditor() }
        hotkeys.install()
    }

    private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(model: model) }
        settingsWindow?.show()
    }

    private func showPromptEditor() {
        if promptWindow == nil { promptWindow = PromptEditorWindow(model: model, promptId: nil) }
        promptWindow?.show()
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
