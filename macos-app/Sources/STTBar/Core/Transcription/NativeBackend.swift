import Foundation

/// Native record→transcribe→clean→replace pipeline behind the Phase-1
/// TranscriptionBackend seam. Server mode (remote / self-hosted Whisper).
final class NativeBackend: TranscriptionBackend {
    private let configProvider: () -> TranscriptionConfig
    private let recorder: AudioRecorder
    private let remote: RemoteTranscriber
    private let local: LocalTranscriber
    private let llm: LLMClient

    init(config: @escaping () -> TranscriptionConfig,
         recorder: AudioRecorder = AudioRecorder(),
         remote: RemoteTranscriber = RemoteTranscriber(),
         local: LocalTranscriber = LocalTranscriber(),
         llm: LLMClient = LLMClient()) {
        self.configProvider = config
        self.recorder = recorder
        self.remote = remote
        self.local = local
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
                let source = TranscriptionSource(rawValue: config.source) ?? .server
                let transcriber: Transcriber = Transcribers.isLocal(source) ? local : remote
                let raw = try await transcriber.transcribe(audioURL: audioURL, config: config)
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
                let final = config.replacements.preview(text)
                completion(.success(final))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
