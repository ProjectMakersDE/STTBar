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
    /// "server" | "selfhost" | "local".
    var source: String
    /// WhisperKit model name for local mode (empty = WhisperKit auto-select).
    var localModel: String
    /// Recording input device name; empty means automatic. Only the recorder
    /// reads these two, so they default to the safe automatic behavior for the
    /// transcription-only call sites.
    var audioInputDevice: String = ""
    /// Keep Bluetooth headsets out of automatic input selection so they stay in
    /// high-quality playback mode while dictating.
    var avoidBluetoothMic: Bool = true
    /// Whisper `prompt` form field (STT_PROMPT). Empty = language default,
    /// "off" = none. Context only; it never appears in the transcript.
    var whisperPrompt: String = ""
    /// Ask the server to trim non-speech with Silero VAD (STT_VAD_FILTER).
    var vadFilter: Bool = true
    /// Beam search width (STT_BEAM_SIZE). Empty = server default.
    var beamSize: String = "5"
    /// Allow re-decoding at higher temperatures (STT_TEMPERATURE_FALLBACK).
    var temperatureFallback: Bool = false

    static let maxBeamSize = 8

    /// The `beam_size` form field, or nil when it should not be sent.
    static func beamSizeParam(for value: String) -> String? {
        guard let n = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), n >= 1 else { return nil }
        return String(min(n, maxBeamSize))
    }

    static func defaultPrompt(language: String) -> String? {
        switch languageParam(for: language)?.lowercased() {
        case "de": return "Guten Tag, das ist ein Diktat. Ich spreche jetzt einen Text mit Satzzeichen, Groß- und Kleinschreibung ein."
        case "en": return "Hello, this is a dictation. I am now speaking a text with punctuation and proper capitalization."
        default: return nil
        }
    }

    /// The Whisper `prompt` form field, or nil when none should be sent.
    static func promptParam(for prompt: String, language: String) -> String? {
        let v = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.lowercased() == "off" { return nil }
        return v.isEmpty ? defaultPrompt(language: language) : v
    }

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
            transcribeTimeout: TimeInterval(Int(model.transcribeTimeout) ?? 30),
            postprocessTimeout: TimeInterval(Int(model.postprocessTimeout) ?? 60),
            temperature: 0,
            reasoning: "off",
            replacements: model.replacements,
            source: model.transcriptionSource,
            localModel: model.localModel,
            audioInputDevice: model.audioInputDevice,
            avoidBluetoothMic: model.avoidBluetoothMic,
            whisperPrompt: model.whisperPrompt,
            vadFilter: model.vadFilter,
            beamSize: model.beamSize,
            temperatureFallback: model.temperatureFallback)
    }
}
