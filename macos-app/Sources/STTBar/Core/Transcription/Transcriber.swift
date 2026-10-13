import Foundation
import FluidAudio
import WhisperKit

/// Abstracts where the recorded WAV becomes text: a remote/self-hosted Whisper
/// server (URLSession) or an in-process model (offline).
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

/// Local offline transcription via FluidAudio (Parakeet) or WhisperKit. One
/// shared instance keeps the loaded model in memory, so the app can load and
/// warm it at launch and the first dictation does not pay for it. Models
/// download into the sandbox container.
actor LocalTranscriber: Transcriber {
    static let shared = LocalTranscriber()

    private var pipe: WhisperKit?
    private var parakeet: (manager: AsrManager, version: AsrModelVersion)?
    private var loadedModel: String?
    private var working = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Container directory local model files download into.
    static var modelsDirectory: URL {
        InstallPaths.resolve().appendingPathComponent("models", isDirectory: true)
    }

    /// Readiness, download and transcription must agree on the selected model.
    static func requestedModelName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("distil-"), !trimmed.hasPrefix("distil-whisper_") {
            return "distil-whisper_" + trimmed
        }
        return trimmed.isEmpty ? LocalModels.defaultModel : trimmed
    }

    static func decodingOptions(language: String) -> DecodingOptions {
        let language = TranscriptionConfig.languageParam(for: language)?.lowercased()
        return DecodingOptions(language: language, detectLanguage: language == nil, skipSpecialTokens: true)
    }

    /// Parakeet detects the language itself. The hint only filters tokens of
    /// the wrong script, so unknown codes and "auto" pass nil.
    static func parakeetLanguage(_ language: String) -> Language? {
        TranscriptionConfig.languageParam(for: language).flatMap { Language(rawValue: $0.lowercased()) }
    }

    /// A complete selected cache must open directly. WhisperKit's download
    /// setup otherwise contacts the model repository even for cached weights.
    static func whisperKitConfig(model: String, cachedFolder: URL?, downloadBase: URL) -> WhisperKitConfig {
        WhisperKitConfig(model: model, downloadBase: downloadBase,
                         modelFolder: cachedFolder?.path, prewarm: true, load: true, download: cachedFolder == nil)
    }

    private func acquire() async {
        if working { await withCheckedContinuation { waiting.append($0) } }
        else { working = true }
    }

    private func release() {
        if waiting.isEmpty { working = false }
        else { waiting.removeFirst().resume() }
    }

    /// Downloads the model if needed, loads it and runs one second of silence
    /// through it. CoreML compiles for the Neural Engine on the first
    /// inference, which takes minutes for large models on older chips.
    func prepare(model name: String) async throws {
        await acquire()
        defer { release() }
        try await loadIfNeeded(Self.requestedModelName(name))
    }

    func isLoaded(_ name: String) -> Bool { loadedModel == Self.requestedModelName(name) }

    private func loadIfNeeded(_ requested: String) async throws {
        guard loadedModel != requested else { return }
        await MainActor.run { LocalModelStatus.shared.set(.loading(model: requested)) }
        let start = Date()
        do {
            pipe = nil
            await parakeet?.manager.cleanup()
            parakeet = nil
            loadedModel = nil
            try? FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
            let silence = [Float](repeating: 0, count: 16_000)
            switch LocalModels.engine(for: requested) {
            case .parakeet(let version):
                let models = try await AsrModels.downloadAndLoad(
                    to: LocalModels.parakeetDirectory(version, in: Self.modelsDirectory), version: version)
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                var state = TdtDecoderState.make(decoderLayers: version.decoderLayers)
                _ = try await manager.transcribe(silence, decoderState: &state)
                parakeet = (manager, version)
            case .whisper:
                let cached = OnboardingReadiness.cachedLocalModelFolder(requested, in: Self.modelsDirectory)
                let kit = try await WhisperKit(Self.whisperKitConfig(model: requested, cachedFolder: cached,
                                                                     downloadBase: Self.modelsDirectory))
                _ = try await kit.transcribe(audioArray: silence)
                pipe = kit
            }
            loadedModel = requested
            let seconds = Date().timeIntervalSince(start)
            AppLogger.log("local_model_ready model=\(requested) loadMs=\(Int(seconds * 1000))")
            await MainActor.run { LocalModelStatus.shared.set(.ready(model: requested, seconds: seconds)) }
        } catch {
            AppLogger.log("local_model_failed model=\(requested) \(error.localizedDescription)")
            await MainActor.run {
                LocalModelStatus.shared.set(.failed(model: requested, message: error.localizedDescription))
            }
            throw error
        }
    }

    func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        try await loadIfNeeded(Self.requestedModelName(config.localModel))
        try Task.checkCancellation()
        let text: String
        if let parakeet {
            var state = TdtDecoderState.make(decoderLayers: parakeet.version.decoderLayers)
            let result = try await parakeet.manager.transcribe(audioURL, decoderState: &state,
                                                       language: Self.parakeetLanguage(config.language))
            text = result.text
        } else if let pipe {
            let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: Self.decodingOptions(language: config.language))
            text = results.map { $0.text }.joined(separator: " ")
        } else {
            return ""
        }
        try Task.checkCancellation()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Transcribers {
    static func isLocal(_ source: TranscriptionSource) -> Bool { source == .local }
}
