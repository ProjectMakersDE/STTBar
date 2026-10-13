import Foundation
import WhisperKit

/// Abstracts where the recorded WAV becomes text: a remote/self-hosted Whisper
/// server (URLSession) or in-process WhisperKit (offline).
protocol Transcriber {
    func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String
}

/// Server / self-host: delegates to the Phase-2 multipart client.
struct RemoteTranscriber: Transcriber {
    var client = WhisperClient()
    func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String {
        try await client.transcribe(audioURL: audioURL, config: config)
    }
}

/// Local offline transcription via WhisperKit/CoreML. The pipeline is built
/// lazily and cached; it rebuilds only when the selected model changes. Models
/// download into the sandbox container (`downloadBase`).
actor LocalTranscriber: Transcriber {
    private var pipe: WhisperKit?
    private var loadedModel: String?
    private var working = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Container directory WhisperKit downloads/caches model files into.
    static var modelsDirectory: URL {
        InstallPaths.resolve().appendingPathComponent("models", isDirectory: true)
    }

    /// Readiness, download and transcription must agree on the selected model.
    static func requestedModelName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("distil-"), !trimmed.hasPrefix("distil-whisper_") {
            return "distil-whisper_" + trimmed
        }
        return trimmed.isEmpty ? WhisperKit.recommendedModels().default : trimmed
    }

    static func decodingOptions(language: String) -> DecodingOptions {
        let language = TranscriptionConfig.languageParam(for: language)?.lowercased()
        return DecodingOptions(language: language, detectLanguage: language == nil, skipSpecialTokens: true)
    }

    /// A complete selected cache must open directly. WhisperKit's download
    /// setup otherwise contacts the model repository even for cached weights.
    static func whisperKitConfig(model: String, cachedFolder: URL?, downloadBase: URL) -> WhisperKitConfig {
        WhisperKitConfig(model: model, downloadBase: downloadBase,
                         modelFolder: cachedFolder?.path, load: true, download: cachedFolder == nil)
    }

    private func acquire() async {
        if working { await withCheckedContinuation { waiting.append($0) } }
        else { working = true }
    }

    private func release() {
        if waiting.isEmpty { working = false }
        else { waiting.removeFirst().resume() }
    }

    func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        let requestedModel = Self.requestedModelName(config.localModel)
        if pipe == nil || loadedModel != requestedModel {
            try? FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
            let cached = OnboardingReadiness.cachedLocalModelFolder(requestedModel, in: Self.modelsDirectory)
            let wkConfig = Self.whisperKitConfig(model: requestedModel, cachedFolder: cached, downloadBase: Self.modelsDirectory)
            pipe = try await WhisperKit(wkConfig)
            loadedModel = requestedModel
        }
        try Task.checkCancellation()
        guard let pipe else { return "" }
        let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: Self.decodingOptions(language: config.language))
        try Task.checkCancellation()
        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Transcribers {
    static func isLocal(_ source: TranscriptionSource) -> Bool { source == .local }
}
