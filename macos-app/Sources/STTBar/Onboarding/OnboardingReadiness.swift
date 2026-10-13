import AVFoundation
import Foundation

/// Decides whether the first-run wizard should appear and why. The core is a
/// pure predicate (`blockingReasons`) so it is fully unit-testable; thin wrappers
/// read live state (permissions, downloaded models, the completion flag).
enum OnboardingReadiness {

    // MARK: Completion flag (UserDefaults)

    static let completedKey = "onboardingCompletedAt"

    static var isCompleted: Bool {
        UserDefaults.standard.object(forKey: completedKey) != nil
    }

    static func markCompleted(_ defaults: UserDefaults = .standard) {
        defaults.set(Int(Date().timeIntervalSince1970), forKey: completedKey)
    }

    static func resetCompleted(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: completedKey)
    }

    // MARK: Pure readiness predicate

    /// The minimum facts needed to decide if a dictation can succeed. Accessibility
    /// is intentionally absent: missing it only downgrades paste to clipboard, so
    /// it is a warning, never a hard blocker.
    struct Inputs: Equatable {
        var source: String          // "server" | "selfhost" | "local"
        var localModelDownloaded: Bool
        var whisperURLValid: Bool
        var micAuthorized: Bool
    }

    /// Reasons the current config cannot produce a dictation. Empty == usable.
    static func blockingReasons(_ i: Inputs) -> [String] {
        var reasons: [String] = []
        if !i.micAuthorized { reasons.append("microphone") }
        if i.source == TranscriptionSource.local.rawValue {
            if !i.localModelDownloaded { reasons.append("localModel") }
        } else if i.source == TranscriptionSource.server.rawValue || i.source == TranscriptionSource.selfHost.rawValue {
            if !i.whisperURLValid { reasons.append("serverURL") }
        } else {
            reasons.append("source")
        }
        return reasons
    }

    static func isUsable(_ i: Inputs) -> Bool { blockingReasons(i).isEmpty }

    // MARK: Live wrappers

    static func currentInputs(model: SettingsModel) -> Inputs {
        Inputs(
            source: model.transcriptionSource,
            localModelDownloaded: localModelDownloaded(model.localModel),
            whisperURLValid: isValidHTTPURL(model.whisperURL),
            micAuthorized: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
    }

    /// The wizard is needed on a fresh install (no flag) or whenever the config
    /// is unusable (self-heal).
    static func needsOnboarding(model: SettingsModel) -> Bool {
        !isCompleted || !isUsable(currentInputs(model: model))
    }

    // MARK: Helpers

    /// Automatic selection must mean the same model in setup and transcription.
    /// The device recommendation is local; readiness never contacts the Hub.
    static func requestedLocalModel(_ name: String) -> String {
        LocalTranscriber.requestedModelName(name)
    }

    /// Requires the selected model's three compiled components and its tokenizer
    /// data/config cache. This checks cache completeness, not CoreML inference.
    static func localModelDownloaded(_ name: String = "", in dir: URL = LocalTranscriber.modelsDirectory) -> Bool {
        cachedLocalModelFolder(name, in: dir) != nil
    }

    static func cachedLocalModelFolder(_ name: String, in dir: URL = LocalTranscriber.modelsDirectory) -> URL? {
        let requested = requestedLocalModel(name)
        guard let it = FileManager.default.enumerator(at: dir,
                                                      includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles]) else { return nil }
        for case let folder as URL in it {
            if folder.pathExtension == "mlmodelc" { it.skipDescendants(); continue }
            guard folder.lastPathComponent == requested || folder.lastPathComponent == "openai_whisper-\(requested)",
                  (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let complete = ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { component in
                let metadata = folder.appendingPathComponent("\(component).mlmodelc/coremldata.bin")
                let values = try? metadata.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                return values?.isRegularFile == true && (values?.fileSize ?? 0) > 0
            }
            guard complete else { continue }
            var variant = folder.lastPathComponent
            for prefix in ["openai_whisper-", "distil-whisper_distil-"] where variant.hasPrefix(prefix) {
                variant.removeFirst(prefix.count)
            }
            let tokenizerVariant = ["large-v3", "large-v2", "large", "medium.en", "medium", "small.en", "small", "base.en", "base", "tiny.en", "tiny"]
                .first { variant == $0 || variant.hasPrefix($0 + "-") || variant.hasPrefix($0 + "_") }
            var tokenizerPaths = [dir, folder]
            if let variant = tokenizerVariant {
                tokenizerPaths.insert(dir.appendingPathComponent("models/openai/whisper-\(variant)"), at: 0)
                tokenizerPaths.append(folder.appendingPathComponent("models/openai/whisper-\(variant)"))
            }
            // WhisperKit tries the first cache containing tokenizer.json; a
            // broken higher-priority cache must not be hidden by a later one.
            if let tokenizerFolder = tokenizerPaths.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("tokenizer.json").path) }),
               tokenizerIsCached(in: tokenizerFolder) {
                return folder
            }
        }
        return nil
    }

    private static func tokenizerIsCached(in folder: URL) -> Bool {
        func json(_ name: String) -> [String: Any]? {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return value as? [String: Any]
        }
        // Hub's tokenizer_config is optional for generic models, but the pinned
        // WhisperKit AutoTokenizer requires it (no bundled fallback).
        guard let config = json("tokenizer_config.json"),
              let tokenizerClass = config["tokenizer_class"] as? String, !tokenizerClass.isEmpty,
              let model = json("tokenizer.json")?["model"] as? [String: Any],
              model["type"] as? String == "BPE",
              let vocab = model["vocab"] as? [String: Int], !vocab.isEmpty,
              let merges = model["merges"] as? [Any] else { return false }
        // Missing merges triggers a fatalError in the dependency. Both the old
        // space-separated and new two-string formats are supported by it.
        guard merges.allSatisfy({ merge in
            if let pair = merge as? [String] { return pair.count == 2 }
            if let pair = merge as? String { return pair.components(separatedBy: " ").count == 2 }
            return false
        }) else { return false }
        let modelConfig = folder.appendingPathComponent("config.json")
        return !FileManager.default.fileExists(atPath: modelConfig.path) || json("config.json") != nil
    }

    /// The source the wizard should preselect on a fresh, never-completed run.
    /// A downloaded local model wins; a deliberately configured remote (valid,
    /// non-localhost URL) is kept; otherwise a fresh user is steered to local.
    static func preferredInitialSource(model: SettingsModel) -> String {
        preferredInitialSource(localModelDownloaded: localModelDownloaded(model.localModel),
                               whisperURL: model.whisperURL,
                               currentSource: model.transcriptionSource)
    }

    /// Pure core of the preselect rule (testable without a SettingsModel).
    static func preferredInitialSource(localModelDownloaded: Bool, whisperURL: String, currentSource: String) -> String {
        if localModelDownloaded { return TranscriptionSource.local.rawValue }
        let host = URL(string: whisperURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased() ?? ""
        let isRealRemote = isValidHTTPURL(whisperURL)
            && host != "localhost" && !host.hasPrefix("127.") && host != "[::1]" && host != "::1"
        return isRealRemote ? currentSource : TranscriptionSource.local.rawValue
    }

    static func isValidHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme else { return false }
        return ["http", "https"].contains(scheme.lowercased()) && !(url.host ?? "").isEmpty
    }
}
