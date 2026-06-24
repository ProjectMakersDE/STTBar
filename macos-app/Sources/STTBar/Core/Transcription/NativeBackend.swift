import Foundation

/// Native record→transcribe→clean→replace pipeline behind the Phase-1
/// TranscriptionBackend seam. Server mode (remote / self-hosted Whisper).
final class NativeBackend: TranscriptionBackend {
    private let configProvider: () -> TranscriptionConfig
    private let replace: (String) -> String
    private let recorder: AudioRecorder
    private let whisper: WhisperClient
    private let llm: LLMClient

    init(config: @escaping () -> TranscriptionConfig,
         replace: @escaping (String) -> String,
         recorder: AudioRecorder = AudioRecorder(),
         whisper: WhisperClient = WhisperClient(),
         llm: LLMClient = LLMClient()) {
        self.configProvider = config
        self.replace = replace
        self.recorder = recorder
        self.whisper = whisper
        self.llm = llm
    }

    var isRecording: Bool { recorder.isRecording }

    static func usesLLM(_ mode: SttMode) -> Bool { mode == .full || mode == .english }
    static func translateTarget(_ mode: SttMode) -> String? { mode == .english ? "English" : nil }

    func start(mode: SttMode) throws {
        RuntimePaths.ensureDirectory()
        try recorder.start(outputURL: RuntimePaths.recordingFile)
    }

    func cancel() { recorder.cancel() }

    func stop(mode: SttMode, completion: @escaping (Result<String, Error>) -> Void) {
        guard let audioURL = recorder.stop() else { completion(.success("")); return }
        let config = configProvider()
        Task {
            do {
                let raw = try await whisper.transcribe(audioURL: audioURL, config: config)
                var text = raw
                if Self.usesLLM(mode) && config.postprocessEnabled {
                    do {
                        text = try await llm.clean(transcript: raw, config: config, translateTo: Self.translateTarget(mode))
                    } catch {
                        // STT_AUTO_RAW_FALLBACK: keep the raw transcript on LLM failure.
                        AppLogger.log("llm_cleanup_failed_fallback_raw \(error.localizedDescription)")
                        text = raw
                    }
                }
                let final = replace(text)
                completion(.success(final))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
