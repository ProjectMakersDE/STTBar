import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menu: MenuBarController!
    private var hotkeys: HotkeyManager!
    private var runner: SttRunner!
    private var hud: HudOverlay!
    private var settingsWindow: SettingsWindow?
    private var promptWindow: PromptEditorWindow?
    let installDir = InstallPaths.resolve()

    func applicationDidFinishLaunching(_ notification: Notification) {
        runner = SttRunner(scriptPath: installDir.appendingPathComponent("stt-global.sh").path)
        hud = HudOverlay(runner: runner)
        menu = MenuBarController()
        hotkeys = HotkeyManager()

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
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(installDir: installDir,
                                            onHotkeysChanged: { [weak self] in self?.hotkeys.reload() })
        }
        settingsWindow?.show()
    }

    private func showPromptEditor() {
        if promptWindow == nil { promptWindow = PromptEditorWindow(installDir: installDir) }
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
