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
        } else {
            if !i.whisperURLValid { reasons.append("serverURL") }
        }
        return reasons
    }

    static func isUsable(_ i: Inputs) -> Bool { blockingReasons(i).isEmpty }

    // MARK: Live wrappers

    static func currentInputs(model: SettingsModel) -> Inputs {
        Inputs(
            source: model.transcriptionSource,
            localModelDownloaded: localModelDownloaded(),
            whisperURLValid: isValidHTTPURL(model.whisperURL),
            micAuthorized: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
    }

    /// The wizard is needed on a fresh install (no flag) or whenever the config
    /// is unusable (self-heal).
    static func needsOnboarding(model: SettingsModel) -> Bool {
        !isCompleted || !isUsable(currentInputs(model: model))
    }

    // MARK: Helpers

    /// True if WhisperKit has at least one compiled model (`*.mlmodelc`) cached in
    /// the models directory.
    static func localModelDownloaded(in dir: URL = LocalTranscriber.modelsDirectory) -> Bool {
        guard let it = FileManager.default.enumerator(at: dir,
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]) else { return false }
        for case let url as URL in it where url.pathExtension == "mlmodelc" {
            return true
        }
        return false
    }

    /// The source the wizard should preselect on a fresh, never-completed run.
    /// A downloaded local model wins; a deliberately configured remote (valid,
    /// non-localhost URL) is kept; otherwise a fresh user is steered to local.
    static func preferredInitialSource(model: SettingsModel) -> String {
        preferredInitialSource(localModelDownloaded: localModelDownloaded(),
                               whisperURL: model.whisperURL,
                               currentSource: model.transcriptionSource)
    }

    /// Pure core of the preselect rule (testable without a SettingsModel).
    static func preferredInitialSource(localModelDownloaded: Bool, whisperURL: String, currentSource: String) -> String {
        if localModelDownloaded { return TranscriptionSource.local.rawValue }
        let url = whisperURL.lowercased()
        let isRealRemote = isValidHTTPURL(whisperURL)
            && !url.contains("localhost") && !url.contains("127.0.0.1")
        return isRealRemote ? currentSource : TranscriptionSource.local.rawValue
    }

    static func isValidHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme else { return false }
        return ["http", "https"].contains(scheme.lowercased()) && !(url.host ?? "").isEmpty
    }
}
