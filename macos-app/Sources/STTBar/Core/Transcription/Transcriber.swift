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
final class LocalTranscriber: Transcriber {
    private var pipe: WhisperKit?
    private var loadedModel: String?

    /// Container directory WhisperKit downloads/caches model files into.
    static var modelsDirectory: URL {
        InstallPaths.resolve().appendingPathComponent("models", isDirectory: true)
    }

    func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String {
        if pipe == nil || loadedModel != config.localModel {
            try? FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
            let wkConfig = WhisperKitConfig(
                model: config.localModel.isEmpty ? nil : config.localModel,
                downloadBase: Self.modelsDirectory)
            pipe = try await WhisperKit(wkConfig)
            loadedModel = config.localModel
        }
        guard let pipe else { return "" }
        let results = try await pipe.transcribe(audioPath: audioURL.path)
        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Transcribers {
    static func isLocal(_ source: TranscriptionSource) -> Bool { source == .local }
}
