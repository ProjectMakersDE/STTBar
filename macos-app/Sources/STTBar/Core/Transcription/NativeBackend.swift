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

    func stop(mode: SttMode,
              onPhase: @escaping (TranscriptionPhase) -> Void,
              completion: @escaping (Result<String, Error>) -> Void) {
        guard let audioURL = recorder.stop() else { completion(.success("")); return }
        let config = configProvider()
        let wavBytes = (try? FileManager.default.attributesOfItem(atPath: audioURL.path))?[.size] as? Int
        Task {
            do {
                onPhase(.transcribing)
                let source = TranscriptionSource(rawValue: config.source) ?? .server
                let transcriber: Transcriber = Transcribers.isLocal(source) ? local : remote
                let whisperStart = Date()
                let raw = try await transcriber.transcribe(audioURL: audioURL, config: config)
                let whisperMs = Int(Date().timeIntervalSince(whisperStart) * 1000)
                var text = raw
                var postprocessMs = 0
                if Self.usesLLM(mode) && config.postprocessEnabled {
                    onPhase(.postprocessing)
                    let llmStart = Date()
                    do {
                        text = try await llm.clean(transcript: raw, config: config, translateTo: Self.translateTarget(mode))
                    } catch {
                        // STT_AUTO_RAW_FALLBACK: keep the raw transcript on LLM failure.
                        AppLogger.log("llm_cleanup_failed_fallback_raw \(error.localizedDescription)")
                        text = raw
                    }
                    postprocessMs = Int(Date().timeIntervalSince(llmStart) * 1000)
                }
                let final = config.replacements.preview(text)
                StatusStore.appendRunMetric(RunMetric(
                    schema: 1,
                    timestamp: ISO8601DateFormatter().string(from: Date()),
                    runId: nil,
                    mode: mode.rawValue,
                    wavBytes: wavBytes,
                    recordingMs: nil,
                    whisperMs: whisperMs,
                    whisperTextChars: raw.count,
                    postprocessMs: postprocessMs > 0 ? postprocessMs : nil,
                    outputChars: final.count,
                    pasteStatus: nil))
                completion(.success(final))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
