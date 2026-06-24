import Foundation

/// Immutable snapshot of the settings the native pipeline needs for one run.
/// Taken on the main thread at stop() time, then handed to the async clients.
struct TranscriptionConfig {
    var whisperURL: String
    var whisperModel: String
    var language: String
    var postprocessEnabled: Bool
    var provider: String
    var lmStudioURL: String
    var llmModel: String
    var promptBody: String
    var transcribeTimeout: TimeInterval
    var postprocessTimeout: TimeInterval
    var temperature: Double
    var reasoning: String
    /// Snapshot of the configured word replacements (value type — safe to use
    /// off the main thread inside the async pipeline).
    var replacements: ReplacementStore

    /// The Whisper `language` form field, or nil when auto-detect is requested.
    static func languageParam(for language: String) -> String? {
        let v = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v.isEmpty || v.lowercased() == "auto") ? nil : v
    }

    static func from(_ model: SettingsModel) -> TranscriptionConfig {
        TranscriptionConfig(
            whisperURL: model.whisperURL,
            whisperModel: model.whisperModel,
            language: model.language,
            postprocessEnabled: model.postprocessEnabled,
            provider: model.provider,
            lmStudioURL: model.lmStudioURL,
            llmModel: model.llmModel,
            promptBody: model.prompts.activePrompt?.body ?? "",
            transcribeTimeout: TimeInterval(Int(model.postprocessTimeout) ?? 30),
            postprocessTimeout: TimeInterval(Int(model.postprocessTimeout) ?? 60),
            temperature: 0,
            reasoning: "off",
            replacements: model.replacements)
    }
}
