import SwiftUI

/// Single source the SwiftUI views bind to. Wraps EnvStore + PromptStore +
/// AppSettings and writes through on change.
final class SettingsModel: ObservableObject {
    private var env: EnvStore
    @Published var prompts: PromptStore
    let installDir: URL
    var onHotkeysChanged: (() -> Void)?

    @Published var whisperURL: String { didSet { write("STT_SERVER_URL", whisperURL) } }
    @Published var whisperModel: String { didSet { write("STT_MODEL", whisperModel) } }
    @Published var language: String { didSet { write("STT_LANGUAGE", language) } }
    @Published var postprocessEnabled: Bool { didSet { write("STT_POSTPROCESS_ENABLED", postprocessEnabled ? "1" : "0") } }
    @Published var lmStudioURL: String { didSet { write("STT_POSTPROCESS_URL", lmStudioURL) } }
    @Published var llmModel: String { didSet { write("STT_POSTPROCESS_MODEL", llmModel) } }
    @Published var provider: String { didSet { write("STT_POSTPROCESS_PROVIDER", provider) } }
    @Published var hudAnchor: HudAnchor { didSet { AppSettings.shared.hudAnchor = hudAnchor } }
    @Published var hudBackground: Bool { didSet { AppSettings.shared.hudBackground = hudBackground } }
    @Published var hudBackgroundColor: Color { didSet { AppSettings.shared.hudBackgroundColor = RGBAColor(hudBackgroundColor) } }

    /// Common Whisper model presets surfaced in the picker (free text still allowed).
    static let whisperPresets = [
        "Systran/faster-whisper-large-v3-turbo",
        "Systran/faster-whisper-large-v3",
        "Systran/faster-whisper-medium",
        "Systran/faster-whisper-base",
    ]

    init(installDir: URL) {
        self.installDir = installDir
        let envURL = installDir.appendingPathComponent(".env")
        self.env = (try? EnvStore(url: envURL)) ?? (try! EnvStore(url: envURL))
        self.prompts = (try? PromptStore(directory: installDir, defaultBody: DefaultPrompt.body))
            ?? (try! PromptStore(directory: installDir, defaultBody: DefaultPrompt.body))
        whisperURL = env.value("STT_SERVER_URL") ?? ""
        whisperModel = env.value("STT_MODEL") ?? "Systran/faster-whisper-large-v3-turbo"
        language = env.value("STT_LANGUAGE") ?? "de"
        postprocessEnabled = (env.value("STT_POSTPROCESS_ENABLED") ?? "0") == "1"
        lmStudioURL = env.value("STT_POSTPROCESS_URL") ?? ""
        llmModel = env.value("STT_POSTPROCESS_MODEL") ?? ""
        provider = env.value("STT_POSTPROCESS_PROVIDER") ?? "lmstudio"
        hudAnchor = AppSettings.shared.hudAnchor
        hudBackground = AppSettings.shared.hudBackground
        hudBackgroundColor = AppSettings.shared.hudBackgroundColor.color
        // Ensure .env points at the mirrored active prompt file.
        write("STT_POSTPROCESS_PROMPT_FILE", prompts.activeFileURL.path)
    }

    private func write(_ key: String, _ value: String) { env.set(key, value); try? env.save() }

    // Prompt operations re-publish the store.
    func addPrompt(title: String, body: String) {
        _ = try? prompts.add(title: title, body: body); objectWillChange.send()
    }
    func setActive(_ id: String) { try? prompts.setActive(id); objectWillChange.send() }
    func updatePrompt(_ id: String, title: String, body: String) {
        try? prompts.update(id, title: title, body: body); objectWillChange.send()
    }
    func removePrompt(_ id: String) { try? prompts.remove(id); objectWillChange.send() }

    func hotkey(_ mode: SttMode) -> Hotkey { AppSettings.shared.hotkey(mode) }
    func setHotkey(_ hk: Hotkey, for mode: SttMode) {
        AppSettings.shared.setHotkey(hk, for: mode)
        onHotkeysChanged?()
        objectWillChange.send()
    }
}
