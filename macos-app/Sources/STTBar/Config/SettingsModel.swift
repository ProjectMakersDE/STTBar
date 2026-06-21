import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Single source the SwiftUI views bind to. Env values are edited as a draft
/// and written only when the user applies them; local app-only preferences
/// remain immediate because they do not risk a half-written `.env`.
final class SettingsModel: ObservableObject {
    private var env: EnvStore
    @Published var prompts: PromptStore
    @Published var profiles: ProfileStore
    @Published var replacements: ReplacementStore
    let installDir: URL
    var onHotkeysChanged: (() -> Void)?

    @Published var whisperURL: String = ""
    @Published var whisperModel: String = ""
    @Published var language: String = "de"
    @Published var transcribeTimeout: String = "30"
    @Published var postprocessEnabled: Bool = false
    @Published var lmStudioURL: String = ""
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

    @Published var hudAnchor: HudAnchor { didSet { AppSettings.shared.hudAnchor = hudAnchor } }
    @Published var hudBackground: Bool { didSet { AppSettings.shared.hudBackground = hudBackground } }
    @Published var hudBackgroundColor: Color { didSet { AppSettings.shared.hudBackgroundColor = RGBAColor(hudBackgroundColor) } }
    @Published var showHudTimer: Bool { didSet { AppSettings.shared.showHudTimer = showHudTimer } }
    @Published var showHudIcon: Bool { didSet { AppSettings.shared.showHudIcon = showHudIcon } }
    @Published var showHudWaveform: Bool { didSet { AppSettings.shared.showHudWaveform = showHudWaveform } }
    @Published var hudFollowActiveScreen: Bool { didSet { AppSettings.shared.hudFollowActiveScreen = hudFollowActiveScreen } }
    @Published var hudOffsetX: Int { didSet { AppSettings.shared.hudOffsetX = hudOffsetX } }
    @Published var hudOffsetY: Int { didSet { AppSettings.shared.hudOffsetY = hudOffsetY } }
    @Published var hudScale: Double { didSet { AppSettings.shared.hudScale = hudScale } }
    @Published var hudWaveDecaySpeed: Double { didSet { AppSettings.shared.hudWaveDecaySpeed = hudWaveDecaySpeed } }
    @Published var hudWaveStyle: HudWaveStyle { didSet { AppSettings.shared.hudWaveStyle = hudWaveStyle } }

    @Published var validationMessage: String?
    @Published var saveMessage: String?
    @Published var hotkeyStatuses: [HotkeyRegistrationStatus] = []
    @Published var updateMessage: String?
    @Published var updateURL: URL?
    @Published var updateState: UpdateState = .idle
    @Published var latestVersion: String?
    var appAssetURL: URL?
    var scriptsAssetURL: URL?
    var appSha256URL: URL?

    enum UpdateState: Equatable { case idle, checking, upToDate, available, downloading, installing, failed }

    static let defaultUpdateRepository = "ProjectMakersDE/STTBar"

    /// The GitHub `owner/repo` slug used for update checks.
    var updateRepository: String { env.value("STTBAR_UPDATE_REPOSITORY") ?? Self.defaultUpdateRepository }

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
        self.prompts = (try? PromptStore(directory: installDir, defaultPrompts: DefaultPrompt.seeds))
            ?? (try! PromptStore(directory: installDir, defaultPrompts: DefaultPrompt.seeds))
        self.profiles = ProfileStore(directory: installDir)
        self.replacements = ReplacementStore(directory: installDir)
        self.hudAnchor = AppSettings.shared.hudAnchor
        self.hudBackground = AppSettings.shared.hudBackground
        self.hudBackgroundColor = AppSettings.shared.hudBackgroundColor.color
        self.showHudTimer = AppSettings.shared.showHudTimer
        self.showHudIcon = AppSettings.shared.showHudIcon
        self.showHudWaveform = AppSettings.shared.showHudWaveform
        self.hudFollowActiveScreen = AppSettings.shared.hudFollowActiveScreen
        self.hudOffsetX = AppSettings.shared.hudOffsetX
        self.hudOffsetY = AppSettings.shared.hudOffsetY
        self.hudScale = AppSettings.shared.hudScale
        self.hudWaveDecaySpeed = AppSettings.shared.hudWaveDecaySpeed
        self.hudWaveStyle = AppSettings.shared.hudWaveStyle
        loadEnvDraft()
        if env.value("STTBAR_UPDATE_REPOSITORY") == nil {
            write("STTBAR_UPDATE_REPOSITORY", Self.defaultUpdateRepository)
        }
        write("STT_POSTPROCESS_PROMPT_FILE", prompts.activeFileURL.path)
        try? env.save()
    }

    func applyEnvChanges() {
        guard validateDraft() else { return }
        backupEnv()
        write("STT_SERVER_URL", whisperURL)
        write("STT_MODEL", whisperModel)
        write("STT_LANGUAGE", language)
        write("STT_TRANSCRIBE_TIMEOUT", transcribeTimeout)
        write("STT_POSTPROCESS_ENABLED", postprocessEnabled ? "1" : "0")
        write("STT_POSTPROCESS_URL", lmStudioURL)
        write("STT_POSTPROCESS_MODEL", llmModel)
        write("STT_POSTPROCESS_PROVIDER", provider)
        write("STT_POSTPROCESS_TIMEOUT", postprocessTimeout)
        write("STT_POSTPROCESS_WARN_SECONDS", postprocessWarnSeconds)
        write("STT_AUTO_RAW_FALLBACK", autoRawFallback ? "1" : "0")
        write("STT_PREWARM_ENABLED", prewarmEnabled ? "1" : "0")
        write("STT_KEEP_MODEL_WARM_SECONDS", keepModelWarmSeconds)
        write("STT_MAX_RECORDING_SECONDS", maxRecordingSeconds)
        write("STT_HISTORY_ENABLED", historyEnabled ? "1" : "0")
        write("STT_HISTORY_RETENTION_HOURS", historyRetentionHours)
        write("STT_SENSITIVE_MODE", sensitiveMode ? "1" : "0")
        write("STT_AUDIO_DEVICE", audioInputDevice)
        do {
            try env.save()
            syncAppSettingsFromDraft()
            validationMessage = nil
            saveMessage = "Gespeichert"
        } catch {
            validationMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func revertEnvChanges() {
        env = (try? EnvStore(url: installDir.appendingPathComponent(".env"))) ?? env
        loadEnvDraft()
        saveMessage = "Zurückgesetzt"
    }

    @discardableResult
    func validateDraft() -> Bool {
        func validURL(_ value: String) -> Bool {
            guard let url = URL(string: value), let scheme = url.scheme else { return false }
            return ["http", "https"].contains(scheme)
        }
        if !validURL(whisperURL) {
            validationMessage = "Whisper-URL muss mit http:// oder https:// beginnen."
            return false
        }
        if whisperModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationMessage = "Whisper-Modell darf nicht leer sein."
            return false
        }
        if Int(transcribeTimeout).map({ $0 > 0 }) != true {
            validationMessage = "Whisper-Timeout muss eine positive Zahl sein."
            return false
        }
        if postprocessEnabled {
            if !validURL(lmStudioURL) {
                validationMessage = "LLM-URL muss mit http:// oder https:// beginnen."
                return false
            }
            if llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationMessage = "LLM-Modell darf nicht leer sein."
                return false
            }
        }
        if !["lmstudio", "openai"].contains(provider) {
            validationMessage = "Provider muss lmstudio oder openai sein."
            return false
        }
        for value in [postprocessTimeout, postprocessWarnSeconds, keepModelWarmSeconds, maxRecordingSeconds, historyRetentionHours] {
            if Int(value).map({ $0 >= 0 }) != true {
                validationMessage = "Timeouts und Zeitwerte müssen Zahlen sein."
                return false
            }
        }
        validationMessage = nil
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
            validationMessage = "Profil konnte nicht gespeichert werden: \(error.localizedDescription)"
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
            saveMessage = "Wörterbuch gespeichert"
        } catch {
            validationMessage = "Wörterbuch konnte nicht gespeichert werden: \(error.localizedDescription)"
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
        let bundle = ExportBundle(env: exportEnvValues(), prompts: prompts.prompts, replacements: replacements.entries, profiles: profiles.profiles)
        if let data = try? JSONEncoder().encode(bundle) {
            try? data.write(to: url, options: .atomic)
            saveMessage = "Exportiert"
        }
    }

    func importBundle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(ExportBundle.self, from: data)
        else { return }
        for (key, value) in bundle.env { write(key, value) }
        try? env.save()
        for prompt in bundle.prompts {
            if prompts.prompts.contains(where: { $0.id == prompt.id }) {
                try? prompts.update(prompt.id, title: prompt.title, body: prompt.body)
            } else {
                _ = try? prompts.add(title: prompt.title, body: prompt.body)
            }
        }
        try? replacements.update(bundle.replacements)
        for profile in bundle.profiles {
            try? profiles.upsert(profile, makeActive: false)
        }
        loadEnvDraft()
        objectWillChange.send()
        saveMessage = "Importiert"
    }

    func checkForUpdates() {
        let version = VersionInfo.load(installDir: installDir)
        let repository = updateRepository
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            updateMessage = L("Update-URL ist ungültig.", "Update URL is invalid.")
            updateState = .failed
            return
        }
        updateMessage = L("Suche Releases auf GitHub…", "Checking GitHub releases…")
        updateState = .checking
        updateURL = nil
        appAssetURL = nil; scriptsAssetURL = nil; appSha256URL = nil
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("STTBar/\(version.appVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let message: String
            var releaseURL: URL?
            var state: UpdateState = .idle
            var assets: [GitHubAsset] = []
            var latestVersion: String?
            defer {
                DispatchQueue.main.async {
                    self.updateMessage = message
                    self.updateURL = releaseURL
                    self.updateState = state
                    self.latestVersion = latestVersion
                    self.appAssetURL = Self.pickAsset(assets, name: "STTBar.app.zip")
                    self.scriptsAssetURL = Self.pickAsset(assets, name: "stt-scripts.zip")
                    self.appSha256URL = Self.pickAsset(assets, name: "STTBar.app.zip.sha256")
                }
            }

            if let error {
                message = L("Update-Check fehlgeschlagen: ", "Update check failed: ") + error.localizedDescription
                state = .failed
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                message = L("Noch kein öffentliches Release gefunden.", "No public release found yet.")
                state = .upToDate
                return
            }
            guard let data,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                message = L("GitHub-Release konnte nicht gelesen werden.", "Could not read the GitHub release.")
                state = .failed
                return
            }
            let latest = Self.normalizedVersion(release.tagName)
            let current = Self.normalizedVersion(version.appVersion)
            releaseURL = URL(string: release.htmlURL)
            assets = release.assets
            latestVersion = latest
            switch Self.compareVersions(latest, current) {
            case .orderedDescending:
                message = L("Update verfügbar: v\(latest) (installiert v\(current))",
                            "Update available: v\(latest) (installed v\(current))")
                state = .available
            case .orderedSame:
                message = L("Aktuell: v\(current)", "Up to date: v\(current)")
                state = .upToDate
            case .orderedAscending:
                message = L("Installiert: v\(current), neuestes Release: v\(latest)",
                            "Installed: v\(current), latest release: v\(latest)")
                state = .upToDate
            }
        }.resume()
    }

    static func pickAsset(_ assets: [GitHubAsset], name: String) -> URL? {
        assets.first { $0.name == name }?.url
    }

    /// Download + install the available update, then relaunch.
    func performUpdate() {
        guard let appZip = appAssetURL else {
            updateState = .failed
            updateMessage = L("Kein App-Asset im Release gefunden.", "No app asset found in the release.")
            return
        }
        updateState = .downloading
        UpdateInstaller.performUpdate(
            appZip: appZip, scriptsZip: scriptsAssetURL, sha256: appSha256URL,
            appBundlePath: Bundle.main.bundlePath, installDir: installDir,
            log: { msg in DispatchQueue.main.async { self.updateMessage = msg } },
            done: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.updateState = .installing
                        self.updateMessage = L("Update installiert. Starte neu…", "Update installed. Relaunching…")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
                    case .failure:
                        self.updateState = .failed
                        self.updateMessage = L("Update fehlgeschlagen. Bitte install.sh manuell ausführen.",
                                               "Update failed. Please run install.sh manually.")
                    }
                }
            })
    }

    private static func normalizedVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }

    private static func compareVersions(_ left: String, _ right: String) -> ComparisonResult {
        let a = versionParts(left)
        let b = versionParts(right)
        for i in 0..<max(a.count, b.count) {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av > bv { return .orderedDescending }
            if av < bv { return .orderedAscending }
        }
        return .orderedSame
    }

    private static func versionParts(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            let digits = part.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }

    func runPromptEval(promptId: String, input: String, completion: @escaping (String) -> Void) {
        guard let prompt = prompts.prompts.first(where: { $0.id == promptId }) else { completion(""); return }
        DispatchQueue.global().async {
            let process = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-lc", "exec \(Self.shellQuote(self.installDir.appendingPathComponent("stt-postprocess.sh").path))"]
            var env = ProcessInfo.processInfo.environment
            env["STT_POSTPROCESS_PROMPT"] = prompt.body
            env["STT_POSTPROCESS_ENABLED"] = "1"
            env["STT_REPLACEMENTS_ENABLED"] = "1"
            env["STT_POSTPROCESS_LOG_ENABLED"] = "0"
            process.environment = env
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = Pipe()
            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(Data(input.utf8))
                try? inputPipe.fileHandleForWriting.close()
                process.waitUntilExit()
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(output) }
            } catch {
                DispatchQueue.main.async { completion("Fehler: \(error.localizedDescription)") }
            }
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

    func hotkey(_ mode: SttMode) -> Hotkey { AppSettings.shared.hotkey(mode) }

    func setHotkey(_ hk: Hotkey, for mode: SttMode) {
        AppSettings.shared.setHotkey(hk, for: mode)
        onHotkeysChanged?()
        objectWillChange.send()
    }

    func resetHotkey(_ mode: SttMode) {
        AppSettings.shared.resetHotkey(mode)
        onHotkeysChanged?()
        objectWillChange.send()
    }

    func hotkeyWarning(for mode: SttMode) -> String? {
        let hk = hotkey(mode)
        if SttMode.allCases.contains(where: { $0 != mode && hotkey($0) == hk }) {
            return "Doppelt belegt"
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
        postprocessEnabled = (env.value("STT_POSTPROCESS_ENABLED") ?? "0") == "1"
        lmStudioURL = env.value("STT_POSTPROCESS_URL") ?? "http://localhost:1234/api/v1/chat"
        llmModel = env.value("STT_POSTPROCESS_MODEL") ?? "qwen/qwen3.5-9b"
        provider = env.value("STT_POSTPROCESS_PROVIDER") ?? "lmstudio"
        postprocessTimeout = env.value("STT_POSTPROCESS_TIMEOUT") ?? "60"
        postprocessWarnSeconds = env.value("STT_POSTPROCESS_WARN_SECONDS") ?? "20"
        autoRawFallback = (env.value("STT_AUTO_RAW_FALLBACK") ?? "1") != "0"
        prewarmEnabled = (env.value("STT_PREWARM_ENABLED") ?? "0") == "1"
        keepModelWarmSeconds = env.value("STT_KEEP_MODEL_WARM_SECONDS") ?? "0"
        maxRecordingSeconds = env.value("STT_MAX_RECORDING_SECONDS") ?? "\(AppSettings.shared.maxRecordingSeconds)"
        historyEnabled = (env.value("STT_HISTORY_ENABLED") ?? (AppSettings.shared.historyEnabled ? "1" : "0")) == "1"
        historyRetentionHours = env.value("STT_HISTORY_RETENTION_HOURS") ?? "\(AppSettings.shared.historyRetentionHours)"
        sensitiveMode = (env.value("STT_SENSITIVE_MODE") ?? (AppSettings.shared.sensitiveMode ? "1" : "0")) == "1"
        audioInputDevice = env.value("STT_AUDIO_DEVICE") ?? ""
        syncAppSettingsFromDraft()
    }

    private func syncAppSettingsFromDraft() {
        AppSettings.shared.prewarmEnabled = prewarmEnabled
        AppSettings.shared.keepModelWarmSeconds = Int(keepModelWarmSeconds) ?? 0
        AppSettings.shared.maxRecordingSeconds = Int(maxRecordingSeconds) ?? 1200
        AppSettings.shared.historyEnabled = historyEnabled
        AppSettings.shared.historyRetentionHours = Int(historyRetentionHours) ?? 24
        AppSettings.shared.sensitiveMode = sensitiveMode
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
            "STT_SERVER_URL": whisperURL,
            "STT_MODEL": whisperModel,
            "STT_LANGUAGE": language,
            "STT_TRANSCRIBE_TIMEOUT": transcribeTimeout,
            "STT_POSTPROCESS_ENABLED": postprocessEnabled ? "1" : "0",
            "STT_POSTPROCESS_URL": lmStudioURL,
            "STT_POSTPROCESS_MODEL": llmModel,
            "STT_POSTPROCESS_PROVIDER": provider,
            "STT_POSTPROCESS_TIMEOUT": postprocessTimeout,
            "STT_AUTO_RAW_FALLBACK": autoRawFallback ? "1" : "0",
            "STT_AUDIO_DEVICE": audioInputDevice,
        ]
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private struct ExportBundle: Codable {
        var env: [String: String]
        var prompts: [Prompt]
        var replacements: [ReplacementEntry]
        var profiles: [SttProfile]
    }
}

/// A downloadable file attached to a GitHub release.
struct GitHubAsset: Decodable {
    let name: String
    let url: URL
    enum CodingKeys: String, CodingKey {
        case name
        case url = "browser_download_url"
    }
}

/// The subset of a GitHub release payload STTBar needs for update checks.
struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let assets: [GitHubAsset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}
