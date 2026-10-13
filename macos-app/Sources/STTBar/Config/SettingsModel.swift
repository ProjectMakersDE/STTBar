import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Single source the SwiftUI views bind to. Env values are edited as a draft
/// and written only when the user applies them; local app-only preferences
/// remain immediate because they do not risk a half-written `.env`.
final class SettingsModel: ObservableObject {
    private var env: EnvStore
    private let appSettings: AppSettings
    private let apiKeyReader: (String) -> String
    private let apiKeyWriter: (String, String) -> Void
    /// False until the keychain was read. A rebuilt self-signed binary gets a
    /// keychain prompt (the item is bound to its cdhash), so the app reads the
    /// keys off the main thread instead of freezing launch until it is answered.
    private var apiKeysLoaded = true
    @Published var prompts: PromptStore
    @Published var profiles: ProfileStore
    @Published var replacements: ReplacementStore
    let installDir: URL
    var onHotkeysChanged: (() -> Void)?
    /// Wired by AppDelegate to the live TranscriptHistoryStore, so the
    /// Settings privacy tab can wipe the stored transcripts.
    var onClearHistory: (() -> Void)?
    /// Lets history expiry react immediately to applied retention changes.
    var onPrivacySettingsChanged: (() -> Void)?
    /// Called after transcription settings were saved, so a newly selected
    /// local model loads in the background right away.
    var onEnvApplied: (() -> Void)?

    func clearHistory() { onClearHistory?() }

    @Published var whisperURL: String = "" {
        didSet { if ApiKeyStore.account(for: whisperURL) != ApiKeyStore.account(for: oldValue) { whisperAPIKey = readApiKey(whisperURL) } }
    }
    /// Optional bearer key for the Whisper endpoint. Lives in the keychain under
    /// the URL's host (ApiKeyStore), so it follows the host, not the field.
    @Published var whisperAPIKey: String = ""
    @Published var whisperModel: String = ""
    @Published var language: String = "de"
    @Published var transcribeTimeout: String = "30"
    /// Whisper style prompt (STT_PROMPT). Empty = language default, "off" = none.
    @Published var whisperPrompt: String = ""
    /// Silero VAD on the server (STT_VAD_FILTER).
    @Published var vadFilter: Bool = true
    /// Beam search width (STT_BEAM_SIZE). Empty = server default.
    @Published var beamSize: String = "5"
    /// Temperature fallback on uncertain audio (STT_TEMPERATURE_FALLBACK).
    @Published var temperatureFallback: Bool = false
    @Published var postprocessEnabled: Bool = false
    @Published var lmStudioURL: String = "" {
        didSet {
            if ApiKeyStore.account(for: lmStudioURL) != ApiKeyStore.account(for: oldValue) { llmAPIKey = readApiKey(lmStudioURL) }
            if let inferred = LLMClient.inferredProvider(for: lmStudioURL) { provider = inferred }
        }
    }
    /// Optional bearer key for the LLM endpoint, e.g. OpenRouter.
    @Published var llmAPIKey: String = ""
    @Published var llmModel: String = ""
    @Published var provider: String = "lmstudio"
    @Published var postprocessTimeout: String = "60"
    @Published var postprocessWarnSeconds: String = "20"
    @Published var autoRawFallback: Bool = true
    @Published var prewarmEnabled: Bool = false
    @Published var keepModelWarmSeconds: String = "0"
    @Published var maxRecordingSeconds: String = "1200"
    @Published var historyEnabled: Bool = false
    @Published var historyRetentionHours: String = "24"
    @Published var sensitiveMode: Bool = false
    /// Recording input device, written to `STT_AUDIO_DEVICE`. Empty = automatic.
    @Published var audioInputDevice: String = ""
    /// Keep Bluetooth headsets out of automatic input selection
    /// (`STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH`, shared with the shell backend).
    /// Recording from a headset drags it out of A2DP into the HFP profile, which
    /// audibly degrades anything playing back at the same time.
    @Published var avoidBluetoothMic: Bool = true
    /// Transcription source: "server" | "selfhost" | "local" (STT_SOURCE).
    @Published var transcriptionSource: String = "server"
    /// Local model name (STT_LOCAL_MODEL): Parakeet or a WhisperKit model. Empty = auto.
    @Published var localModel: String = ""
    /// Load and warm the local model at app launch (STT_LOCAL_PRELOAD), so the
    /// first dictation after a restart does not wait for it.
    @Published var localPreload: Bool = true

    @Published var hudAnchor: HudAnchor { didSet { appSettings.hudAnchor = hudAnchor } }
    @Published var hudBackground: Bool { didSet { appSettings.hudBackground = hudBackground } }
    @Published var hudBackgroundColor: Color { didSet { appSettings.hudBackgroundColor = RGBAColor(hudBackgroundColor) } }
    @Published var showHudTimer: Bool { didSet { appSettings.showHudTimer = showHudTimer } }
    @Published var showHudIcon: Bool { didSet { appSettings.showHudIcon = showHudIcon } }
    @Published var showHudWaveform: Bool { didSet { appSettings.showHudWaveform = showHudWaveform } }
    @Published var hudFollowActiveScreen: Bool { didSet { appSettings.hudFollowActiveScreen = hudFollowActiveScreen } }
    @Published var hudOffsetX: Int { didSet { appSettings.hudOffsetX = hudOffsetX } }
    @Published var hudOffsetY: Int { didSet { appSettings.hudOffsetY = hudOffsetY } }
    @Published var hudScale: Double { didSet { appSettings.hudScale = hudScale } }
    @Published var hudWaveDecaySpeed: Double { didSet { appSettings.hudWaveDecaySpeed = hudWaveDecaySpeed } }
    @Published var hudWaveStyle: HudWaveStyle { didSet { appSettings.hudWaveStyle = hudWaveStyle } }

    @Published var validationMessage: String?
    @Published var saveMessage: String?
    @Published var hotkeyStatuses: [HotkeyRegistrationStatus] = []

    /// Common Whisper model presets surfaced in the picker (free text still allowed).
    static let whisperPresets = [
        "Systran/faster-whisper-large-v3-turbo",
        "Systran/faster-whisper-large-v3",
        "Systran/faster-whisper-medium",
        "Systran/faster-whisper-base",
    ]

    init(installDir: URL, appSettings: AppSettings = .shared,
         apiKeyReader: @escaping (String) -> String = { ApiKeyStore.key(for: $0) },
         apiKeyWriter: @escaping (String, String) -> Void = { ApiKeyStore.setKey($0, for: $1) },
         deferApiKeys: Bool = false) {
        apiKeysLoaded = !deferApiKeys
        self.installDir = installDir
        self.appSettings = appSettings
        self.apiKeyReader = apiKeyReader
        self.apiKeyWriter = apiKeyWriter
        let envURL = installDir.appendingPathComponent(".env")
        self.env = (try? EnvStore(url: envURL)) ?? (try! EnvStore(url: envURL))
        self.prompts = PromptStore.loadOrFallback(directory: installDir, defaultPrompts: DefaultPrompt.seeds)
        self.profiles = ProfileStore(directory: installDir)
        self.replacements = ReplacementStore(directory: installDir)
        self.hudAnchor = appSettings.hudAnchor
        self.hudBackground = appSettings.hudBackground
        self.hudBackgroundColor = appSettings.hudBackgroundColor.color
        self.showHudTimer = appSettings.showHudTimer
        self.showHudIcon = appSettings.showHudIcon
        self.showHudWaveform = appSettings.showHudWaveform
        self.hudFollowActiveScreen = appSettings.hudFollowActiveScreen
        self.hudOffsetX = appSettings.hudOffsetX
        self.hudOffsetY = appSettings.hudOffsetY
        self.hudScale = appSettings.hudScale
        self.hudWaveDecaySpeed = appSettings.hudWaveDecaySpeed
        self.hudWaveStyle = appSettings.hudWaveStyle
        loadEnvDraft()
        write("STT_POSTPROCESS_PROMPT_FILE", prompts.activeFileURL.path)
        try? env.save()
    }

    @discardableResult
    func applyEnvChanges() -> Bool {
        saveMessage = nil
        guard validateDraft() else { return false }
        backupEnv()
        var updated = env
        for (key, value) in exportEnvValues() { updated.set(key, value) }
        do {
            try updated.save()
            env = updated
            saveApiKeys()
            syncAppSettingsFromDraft()
            validationMessage = nil
            saveMessage = L("Gespeichert", "Saved")
            onEnvApplied?()
            return true
        } catch {
            validationMessage = L("Speichern fehlgeschlagen: ", "Saving failed: ") + error.localizedDescription
            return false
        }
    }

    /// Applies the privacy tab without changing or validating a server draft.
    @discardableResult
    func applyPrivacyChanges() -> Bool {
        saveMessage = nil
        guard validatePrivacyDraft() else { return false }
        var updated = env
        for (key, value) in privacyEnvValues() { updated.set(key, value) }
        do {
            try updated.save()
            env = updated
            syncAppSettingsFromDraft()
            validationMessage = nil
            saveMessage = L("Datenschutz gespeichert", "Privacy settings saved")
            objectWillChange.send()
            return true
        } catch {
            validationMessage = L("Speichern fehlgeschlagen: ", "Saving failed: ") + error.localizedDescription
            return false
        }
    }

    var effectiveSensitiveMode: Bool { appSettings.sensitiveMode }
    var effectiveHistoryEnabled: Bool { appSettings.historyEnabled && !appSettings.sensitiveMode }

    var privacyChangesPending: Bool {
        sensitiveMode != appSettings.sensitiveMode || historyEnabled != appSettings.historyEnabled
            || Int(historyRetentionHours) != appSettings.historyRetentionHours
            || prewarmEnabled != appSettings.prewarmEnabled
            || Int(keepModelWarmSeconds) != appSettings.keepModelWarmSeconds
            || Int(maxRecordingSeconds) != appSettings.maxRecordingSeconds
    }

    func revertEnvChanges() {
        env = (try? EnvStore(url: installDir.appendingPathComponent(".env"))) ?? env
        loadEnvDraft()
        validationMessage = nil
        saveMessage = L("Zurückgesetzt", "Reverted")
    }

    @discardableResult
    func validateDraft() -> Bool {
        guard let source = TranscriptionSource(rawValue: transcriptionSource) else {
            validationMessage = L("Ungültige Transkriptions-Quelle.", "Invalid transcription source.")
            return false
        }
        if source != .local && !Self.validHTTPURL(whisperURL) {
            validationMessage = L("Whisper-URL muss mit http:// oder https:// beginnen.", "The Whisper URL must start with http:// or https://.")
            return false
        }
        if source != .local && whisperModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationMessage = L("Whisper-Modell darf nicht leer sein.", "The Whisper model must not be empty.")
            return false
        }
        if source != .local && Int(transcribeTimeout).map({ $0 > 0 }) != true {
            validationMessage = L("Whisper-Timeout muss eine positive Zahl sein.", "The Whisper timeout must be a positive number.")
            return false
        }
        if postprocessEnabled {
            if !Self.validHTTPURL(lmStudioURL) {
                validationMessage = L("LLM-URL muss mit http:// oder https:// beginnen.", "The LLM URL must start with http:// or https://.")
                return false
            }
            if llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationMessage = L("LLM-Modell darf nicht leer sein.", "The LLM model must not be empty.")
                return false
            }
            if !["lmstudio", "openai"].contains(provider) {
                validationMessage = L("Provider muss lmstudio oder openai sein.", "The provider must be lmstudio or openai.")
                return false
            }
            if Int(postprocessTimeout).map({ $0 > 0 }) != true || Int(postprocessWarnSeconds).map({ $0 >= 0 }) != true {
                validationMessage = L("LLM-Timeout muss positiv sein; die Warnschwelle darf nicht negativ sein.",
                                      "The LLM timeout must be positive; its warning threshold must not be negative.")
                return false
            }
        }
        guard validatePrivacyDraft() else { return false }
        validationMessage = nil
        return true
    }

    private static func validHTTPURL(_ value: String) -> Bool {
        guard let url = URLComponents(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty else { return false }
        return true
    }

    private func validatePrivacyDraft() -> Bool {
        guard Int(historyRetentionHours).map({ $0 > 0 }) == true else {
            validationMessage = L("Verlauf-Aufbewahrung muss eine positive Stundenzahl sein.", "History retention must be a positive number of hours.")
            return false
        }
        for value in [keepModelWarmSeconds, maxRecordingSeconds] {
            guard Int(value).map({ $0 >= 0 }) == true else {
                validationMessage = L("Laufzeitwerte müssen nichtnegative Zahlen sein.", "Runtime values must be nonnegative numbers.")
                return false
            }
        }
        return true
    }

    func currentProfile(name: String, id: String = UUID().uuidString) -> SttProfile {
        SttProfile(id: id,
                   name: name,
                   whisperURL: whisperURL,
                   whisperModel: whisperModel,
                   language: language,
                   transcribeTimeout: transcribeTimeout,
                   postprocessEnabled: postprocessEnabled,
                   postprocessURL: lmStudioURL,
                   postprocessModel: llmModel,
                   provider: provider,
                   postprocessTimeout: postprocessTimeout,
                   autoRawFallback: autoRawFallback)
    }

    func saveCurrentProfile(name: String, id: String? = nil) {
        let profile = currentProfile(name: name, id: id ?? UUID().uuidString)
        do {
            try profiles.upsert(profile, makeActive: true)
            objectWillChange.send()
            saveMessage = "Profil gespeichert"
        } catch {
            validationMessage = L("Profil konnte nicht gespeichert werden: ", "Could not save the profile: ") + error.localizedDescription
        }
    }

    func applyProfile(_ profile: SttProfile) {
        whisperURL = profile.whisperURL
        whisperModel = profile.whisperModel
        language = profile.language
        transcribeTimeout = profile.transcribeTimeout
        postprocessEnabled = profile.postprocessEnabled
        lmStudioURL = profile.postprocessURL
        llmModel = profile.postprocessModel
        provider = profile.provider
        postprocessTimeout = profile.postprocessTimeout
        autoRawFallback = profile.autoRawFallback
        try? profiles.setActive(profile.id)
        applyEnvChanges()
    }

    func removeProfile(_ id: String) {
        try? profiles.remove(id)
        objectWillChange.send()
    }

    /// Single entry point for the DE/EN app-language switch: flips the UI
    /// language, the Whisper default (STT_LANGUAGE) and the active built-in
    /// prompt, then persists `.env` + the active-prompt mirror.
    func setAppLanguage(_ lang: AppLanguage) {
        Localization.shared.set(lang)

        language = (lang == .de) ? "de" : "en"
        write("STT_LANGUAGE", language)

        let wantedTitle = (lang == .de) ? DefaultPrompt.germanTitle : DefaultPrompt.englishTitle
        if let prompt = prompts.prompts.first(where: { $0.title == wantedTitle }) {
            try? prompts.setActive(prompt.id)
            write("STT_POSTPROCESS_PROMPT_FILE", prompts.activeFileURL.path)
        }
        try? env.save()
        objectWillChange.send()
    }

    func saveReplacements(_ entries: [ReplacementEntry]) {
        do {
            try replacements.update(entries)
            objectWillChange.send()
            saveMessage = L("Wörterbuch gespeichert", "Vocabulary saved")
        } catch {
            validationMessage = L("Wörterbuch konnte nicht gespeichert werden: ", "Could not save the vocabulary: ") + error.localizedDescription
        }
    }

    func addReplacement() {
        try? replacements.add()
        objectWillChange.send()
    }

    func removeReplacement(_ id: String) {
        try? replacements.remove(id)
        objectWillChange.send()
    }

    func exportBundle() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sttbar-export.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportBundle(to: url)
    }

    func makeExportData() throws -> Data {
        try SettingsBundleCodec.encode(SettingsBundle(version: 1, env: exportEnvValues(), prompts: prompts.prompts,
                                                      replacements: replacements.entries, profiles: profiles.profiles))
    }

    @discardableResult
    func exportBundle(to url: URL) -> Bool {
        saveMessage = nil
        do {
            try makeExportData().write(to: url, options: .atomic)
            validationMessage = nil
            saveMessage = L("Exportiert", "Exported")
            return true
        } catch {
            validationMessage = L("Export fehlgeschlagen: ", "Export failed: ") + error.localizedDescription
            return false
        }
    }

    func importBundle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            importBundle(data: try Data(contentsOf: url))
        } catch {
            saveMessage = nil
            validationMessage = L("Import fehlgeschlagen: ", "Import failed: ") + error.localizedDescription
        }
    }

    @discardableResult
    func importBundle(data: Data) -> Bool {
        saveMessage = nil
        do {
            // Decode and check the allowlist before touching any configuration.
            let bundle = try SettingsBundleCodec.decode(data)
            var updatedEnv = env
            for (key, value) in bundle.env { updatedEnv.set(key, value) }
            var updatedPrompts = prompts
            var updatedProfiles = profiles
            var updatedReplacements = replacements
            let urls = Set([installDir.appendingPathComponent(".env"),
                            installDir.appendingPathComponent("prompts.json"),
                            prompts.activeFileURL, installDir.appendingPathComponent("profiles.json"),
                            replacements.url])
            let snapshots = try urls.map { url -> (URL, Data?, Any?) in
                guard FileManager.default.fileExists(atPath: url.path) else { return (url, nil, nil) }
                let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
                return (url, try Data(contentsOf: url), permissions)
            }
            do {
                for prompt in bundle.prompts {
                    if updatedPrompts.prompts.contains(where: { $0.id == prompt.id }) {
                        try updatedPrompts.update(prompt.id, title: prompt.title, body: prompt.body)
                    } else {
                        _ = try updatedPrompts.add(title: prompt.title, body: prompt.body)
                    }
                }
                try updatedReplacements.update(bundle.replacements)
                for profile in bundle.profiles { try updatedProfiles.upsert(profile, makeActive: false) }
                try updatedEnv.save()
            } catch {
                // An import spans several files: restore the exact old bytes on failure.
                for (url, bytes, permissions) in snapshots {
                    if let bytes {
                        try bytes.write(to: url, options: .atomic)
                        if let permissions { try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path) }
                    }
                    else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                }
                throw error
            }
            env = updatedEnv
            prompts = updatedPrompts
            profiles = updatedProfiles
            replacements = updatedReplacements
            loadEnvDraft()
            validationMessage = nil
            saveMessage = L("Importiert", "Imported")
            objectWillChange.send()
            return true
        } catch {
            validationMessage = L("Import fehlgeschlagen: ", "Import failed: ") + error.localizedDescription
            return false
        }
    }

    func addPrompt(title: String, body: String) {
        _ = try? prompts.add(title: title, body: body)
        objectWillChange.send()
    }

    func setActive(_ id: String) {
        try? prompts.setActive(id)
        write("STT_POSTPROCESS_PROMPT_FILE", prompts.activeFileURL.path)
        try? env.save()
        objectWillChange.send()
    }

    func updatePrompt(_ id: String, title: String, body: String, note: String = "") {
        try? prompts.update(id, title: title, body: body, note: note)
        objectWillChange.send()
    }

    func removePrompt(_ id: String) {
        try? prompts.remove(id)
        objectWillChange.send()
    }

    func hotkey(_ mode: SttMode) -> Hotkey { appSettings.hotkey(mode) }

    func setHotkey(_ hk: Hotkey, for mode: SttMode) {
        appSettings.setHotkey(hk, for: mode)
        onHotkeysChanged?()
        objectWillChange.send()
    }

    func resetHotkey(_ mode: SttMode) {
        appSettings.resetHotkey(mode)
        onHotkeysChanged?()
        objectWillChange.send()
    }

    func hotkeyWarning(for mode: SttMode) -> String? {
        let hk = hotkey(mode)
        if SttMode.allCases.contains(where: { $0 != mode && hotkey($0) == hk }) {
            return L("Doppelt belegt", "Already in use")
        }
        return hk.systemWarning
    }

    func syncHotkeyStatuses(_ statuses: [HotkeyRegistrationStatus]) {
        hotkeyStatuses = statuses
    }

    private func loadEnvDraft() {
        whisperURL = env.value("STT_SERVER_URL") ?? "http://localhost:8082/v1/audio/transcriptions"
        whisperModel = env.value("STT_MODEL") ?? "Systran/faster-whisper-large-v3-turbo"
        language = env.value("STT_LANGUAGE") ?? "de"
        transcribeTimeout = env.value("STT_TRANSCRIBE_TIMEOUT") ?? "30"
        whisperPrompt = env.value("STT_PROMPT") ?? ""
        vadFilter = (env.value("STT_VAD_FILTER") ?? "1") != "0"
        beamSize = env.value("STT_BEAM_SIZE") ?? "5"
        temperatureFallback = (env.value("STT_TEMPERATURE_FALLBACK") ?? "0") == "1"
        postprocessEnabled = (env.value("STT_POSTPROCESS_ENABLED") ?? "0") == "1"
        lmStudioURL = env.value("STT_POSTPROCESS_URL") ?? "http://localhost:1234/api/v1/chat"
        llmModel = env.value("STT_POSTPROCESS_MODEL") ?? "qwen/qwen3.5-9b"
        provider = env.value("STT_POSTPROCESS_PROVIDER") ?? "lmstudio"
        postprocessTimeout = env.value("STT_POSTPROCESS_TIMEOUT") ?? "60"
        postprocessWarnSeconds = env.value("STT_POSTPROCESS_WARN_SECONDS") ?? "20"
        autoRawFallback = (env.value("STT_AUTO_RAW_FALLBACK") ?? "1") != "0"
        prewarmEnabled = (env.value("STT_PREWARM_ENABLED") ?? "0") == "1"
        keepModelWarmSeconds = env.value("STT_KEEP_MODEL_WARM_SECONDS") ?? "0"
        maxRecordingSeconds = env.value("STT_MAX_RECORDING_SECONDS") ?? "\(appSettings.maxRecordingSeconds)"
        historyEnabled = (env.value("STT_HISTORY_ENABLED") ?? (appSettings.historyEnabled ? "1" : "0")) == "1"
        historyRetentionHours = env.value("STT_HISTORY_RETENTION_HOURS") ?? "\(appSettings.historyRetentionHours)"
        sensitiveMode = (env.value("STT_SENSITIVE_MODE") ?? (appSettings.sensitiveMode ? "1" : "0")) == "1"
        audioInputDevice = env.value("STT_AUDIO_DEVICE") ?? ""
        avoidBluetoothMic = (env.value("STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH") ?? "1") != "0"
        transcriptionSource = env.value("STT_SOURCE") ?? "server"
        localModel = env.value("STT_LOCAL_MODEL") ?? ""
        localPreload = (env.value("STT_LOCAL_PRELOAD") ?? "1") != "0"
        whisperAPIKey = readApiKey(whisperURL)
        llmAPIKey = readApiKey(lmStudioURL)
        syncAppSettingsFromDraft()
    }

    private func readApiKey(_ url: String) -> String {
        apiKeysLoaded ? apiKeyReader(url) : ""
    }

    /// Reads both keys on a background queue (used with `deferApiKeys`).
    func loadApiKeysInBackground(completion: (() -> Void)? = nil) {
        let whisper = whisperURL, llm = lmStudioURL, reader = apiKeyReader
        DispatchQueue.global(qos: .userInitiated).async {
            let whisperKey = reader(whisper), llmKey = reader(llm)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.apiKeysLoaded = true
                self.whisperAPIKey = self.whisperURL == whisper ? whisperKey : reader(self.whisperURL)
                self.llmAPIKey = self.lmStudioURL == llm ? llmKey : reader(self.lmStudioURL)
                completion?()
            }
        }
    }

    /// Whisper and LLM can share a host (one OpenAI key for both); then one
    /// keychain entry backs both fields and a blank field must not delete it.
    /// Before the keychain was read the fields are empty, not cleared.
    private func saveApiKeys() {
        guard apiKeysLoaded else { return }
        if ApiKeyStore.account(for: whisperURL) == ApiKeyStore.account(for: lmStudioURL) {
            let shared = llmAPIKey.isEmpty ? whisperAPIKey : llmAPIKey
            apiKeyWriter(shared, lmStudioURL)
            whisperAPIKey = shared
            llmAPIKey = shared
        } else {
            apiKeyWriter(whisperAPIKey, whisperURL)
            apiKeyWriter(llmAPIKey, lmStudioURL)
        }
    }

    private func syncAppSettingsFromDraft() {
        appSettings.prewarmEnabled = prewarmEnabled
        appSettings.keepModelWarmSeconds = Int(keepModelWarmSeconds) ?? 0
        appSettings.maxRecordingSeconds = Int(maxRecordingSeconds) ?? 1200
        appSettings.historyEnabled = historyEnabled
        appSettings.historyRetentionHours = Int(historyRetentionHours) ?? 24
        appSettings.sensitiveMode = sensitiveMode
        onPrivacySettingsChanged?()
    }

    private func write(_ key: String, _ value: String) {
        env.set(key, value)
    }

    private func backupEnv() {
        let source = installDir.appendingPathComponent(".env")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = installDir.appendingPathComponent(".env.backup-\(stamp)")
        try? FileManager.default.copyItem(at: source, to: backup)
    }

    private func exportEnvValues() -> [String: String] {
        [
            "STT_SOURCE": transcriptionSource,
            "STT_LOCAL_MODEL": localModel,
            "STT_LOCAL_PRELOAD": localPreload ? "1" : "0",
            "STT_SERVER_URL": whisperURL,
            "STT_MODEL": whisperModel,
            "STT_LANGUAGE": language,
            "STT_TRANSCRIBE_TIMEOUT": transcribeTimeout,
            "STT_PROMPT": whisperPrompt,
            "STT_VAD_FILTER": vadFilter ? "1" : "0",
            "STT_BEAM_SIZE": beamSize,
            "STT_TEMPERATURE_FALLBACK": temperatureFallback ? "1" : "0",
            "STT_POSTPROCESS_ENABLED": postprocessEnabled ? "1" : "0",
            "STT_POSTPROCESS_URL": lmStudioURL,
            "STT_POSTPROCESS_MODEL": llmModel,
            "STT_POSTPROCESS_PROVIDER": provider,
            "STT_POSTPROCESS_TIMEOUT": postprocessTimeout,
            "STT_POSTPROCESS_WARN_SECONDS": postprocessWarnSeconds,
            "STT_AUTO_RAW_FALLBACK": autoRawFallback ? "1" : "0",
            "STT_AUDIO_DEVICE": audioInputDevice,
            "STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH": avoidBluetoothMic ? "1" : "0",
        ].merging(privacyEnvValues(), uniquingKeysWith: { _, new in new })
    }

    private func privacyEnvValues() -> [String: String] {
        [
            "STT_HISTORY_ENABLED": historyEnabled ? "1" : "0",
            "STT_HISTORY_RETENTION_HOURS": historyRetentionHours,
            "STT_SENSITIVE_MODE": sensitiveMode ? "1" : "0",
            "STT_PREWARM_ENABLED": prewarmEnabled ? "1" : "0",
            "STT_KEEP_MODEL_WARM_SECONDS": keepModelWarmSeconds,
            "STT_MAX_RECORDING_SECONDS": maxRecordingSeconds,
        ]
    }
}

struct SettingsBundle: Codable {
    /// Missing in exports from earlier releases.
    var version: Int?
    var env: [String: String]
    var prompts: [Prompt]
    var replacements: [ReplacementEntry]
    var profiles: [SttProfile]
}

/// Pure serialization: no file panels, preferences or Keychain access.
enum SettingsBundleCodec {
    static let allowedEnvKeys: Set<String> = [
        "STT_SOURCE", "STT_LOCAL_MODEL", "STT_LOCAL_PRELOAD", "STT_SERVER_URL", "STT_MODEL", "STT_LANGUAGE",
        "STT_TRANSCRIBE_TIMEOUT", "STT_PROMPT", "STT_VAD_FILTER", "STT_BEAM_SIZE", "STT_TEMPERATURE_FALLBACK",
        "STT_POSTPROCESS_ENABLED", "STT_POSTPROCESS_URL", "STT_POSTPROCESS_MODEL", "STT_POSTPROCESS_PROVIDER",
        "STT_POSTPROCESS_TIMEOUT", "STT_POSTPROCESS_WARN_SECONDS", "STT_AUTO_RAW_FALLBACK",
        "STT_AUDIO_DEVICE", "STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH", "STT_HISTORY_ENABLED",
        "STT_HISTORY_RETENTION_HOURS", "STT_SENSITIVE_MODE", "STT_PREWARM_ENABLED",
        "STT_KEEP_MODEL_WARM_SECONDS", "STT_MAX_RECORDING_SECONDS",
    ]

    enum BundleError: LocalizedError {
        case unsupportedVersion, unsupportedKey(String), invalidSource
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return L("Diese Export-Version wird nicht unterstützt.", "This export version is not supported.")
            case .unsupportedKey(let key): return L("Unbekannte Einstellung im Import: ", "Unknown imported setting: ") + key
            case .invalidSource: return L("Ungültige Transkriptions-Quelle im Import.", "Invalid imported transcription source.")
            }
        }
    }

    static func encode(_ bundle: SettingsBundle) throws -> Data {
        try validate(bundle)
        return try JSONEncoder().encode(bundle)
    }

    static func decode(_ data: Data) throws -> SettingsBundle {
        let bundle = try JSONDecoder().decode(SettingsBundle.self, from: data)
        try validate(bundle)
        return bundle
    }

    private static func validate(_ bundle: SettingsBundle) throws {
        guard bundle.version == nil || bundle.version == 1 else { throw BundleError.unsupportedVersion }
        if let key = bundle.env.keys.filter({ !allowedEnvKeys.contains($0) }).sorted().first { throw BundleError.unsupportedKey(key) }
        if let source = bundle.env["STT_SOURCE"], TranscriptionSource(rawValue: source) == nil { throw BundleError.invalidSource }
    }
}
