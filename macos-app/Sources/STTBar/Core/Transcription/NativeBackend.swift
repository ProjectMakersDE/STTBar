import Foundation

enum NativePipelineError: LocalizedError {
    case runAlreadyActive, englishRequiresCleanup, englishTranslationFailed(String)
    var errorDescription: String? {
        switch self {
        case .runAlreadyActive:
            return L("Ein Diktat läuft bereits.", "A dictation is already running.")
        case .englishRequiresCleanup:
            return L("Englische Ausgabe benötigt einen aktivierten LLM für die Übersetzung. Aktiviere die Nachbearbeitung oder verwende Roh-Aufnahme.",
                     "English output requires an enabled LLM for translation. Enable post-processing or use raw recording.")
        case .englishTranslationFailed(let reason):
            return L("Übersetzung ins Englische fehlgeschlagen; es wurde kein unübersetzter Text eingefügt. ",
                     "English translation failed; no untranslated text was inserted. ") + reason
        }
    }
}

/// Each recording owns an immutable configuration and a unique audio file.
/// Lifecycle entry points run on the main thread; async work only captures its
/// own run, so late cancellation/completion cannot touch a newer recording.
final class NativeBackend: TranscriptionBackend {
    private struct Run {
        let id = UUID()
        let audioURL: URL
        let config: TranscriptionConfig
    }
    private let configProvider: () -> TranscriptionConfig
    private let recorder: AudioRecording
    private let remote: Transcriber
    private let local: Transcriber
    private let llm: TranscriptCleaning
    private let resolveInput: (TranscriptionConfig) -> (AudioInputResolution, String)
    private let makeRecordingURL: () -> URL
    private let recordMetric: (RunMetric) -> Void
    private let sensitiveMode: () -> Bool
    private let log: (String) -> Void
    private var activeRun: Run?
    private var pipelineTask: Task<Void, Never>?

    init(config: @escaping () -> TranscriptionConfig,
         recorder: AudioRecording = AudioRecorder(),
         remote: Transcriber = RemoteTranscriber(),
         local: Transcriber = LocalTranscriber.shared,
         llm: TranscriptCleaning = LLMClient(),
         resolveInput: @escaping (TranscriptionConfig) -> (AudioInputResolution, String) = {
             AudioInputResolver.resolveLiveWithLabel(selected: $0.audioInputDevice, avoidBluetooth: $0.avoidBluetoothMic)
         },
         recordingURL: @escaping () -> URL = {
             RuntimePaths.directory.appendingPathComponent("recording-\(UUID().uuidString).wav")
         },
         recordMetric: @escaping (RunMetric) -> Void = StatusStore.appendRunMetric,
         sensitiveMode: @escaping () -> Bool = { AppSettings.shared.sensitiveMode },
         log: @escaping (String) -> Void = AppLogger.log) {
        configProvider = config
        self.recorder = recorder
        self.remote = remote
        self.local = local
        self.llm = llm
        self.resolveInput = resolveInput
        makeRecordingURL = recordingURL
        self.recordMetric = recordMetric
        self.sensitiveMode = sensitiveMode
        self.log = log
    }

    var isRecording: Bool { recorder.isRecording }
    var recordingURL: URL? { isRecording ? activeRun?.audioURL : nil }
    var isSensitiveRun: Bool { activeRun?.config.sensitiveMode == true }

    static func usesLLM(_ mode: SttMode) -> Bool { mode == .full || mode == .english }
    static func translateTarget(_ mode: SttMode) -> String? { mode == .english ? "English" : nil }

    func start(mode: SttMode) throws {
        guard activeRun == nil else { throw NativePipelineError.runAlreadyActive }
        var config = configProvider()
        config.sensitiveMode = config.sensitiveMode || sensitiveMode()
        let run = Run(audioURL: makeRecordingURL(), config: config)
        activeRun = run
        do {
            try FileManager.default.createDirectory(at: run.audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let resolveStart = Date()
            let (input, inputLabel) = resolveInput(config)
            let resolveMs = Int(Date().timeIntervalSince(resolveStart) * 1000)
            let engineStart = Date()
            try recorder.start(outputURL: run.audioURL, input: input)
            log("record_start resolveMs=\(resolveMs) engineMs=\(Int(Date().timeIntervalSince(engineStart) * 1000)) \(inputLabel)")
        } catch {
            recorder.cancel()
            try? FileManager.default.removeItem(at: run.audioURL)
            activeRun = nil
            throw error
        }
    }

    func cancel() {
        let cancelled = activeRun
        activeRun = nil
        pipelineTask?.cancel()
        pipelineTask = nil
        recorder.cancel()
        if let cancelled { try? FileManager.default.removeItem(at: cancelled.audioURL) }
    }

    func stop(mode: SttMode,
              onPhase: @escaping (TranscriptionPhase) -> Void,
              completion: @escaping (Result<String, Error>) -> Void) {
        guard let run = activeRun, pipelineTask == nil else { return completion(.success("")) }
        let stopStart = Date()
        let stopped = recorder.stop()
        log("record_stop engineMs=\(Int(Date().timeIntervalSince(stopStart) * 1000))")
        guard stopped != nil else {
            try? FileManager.default.removeItem(at: run.audioURL)
            finish(run: run, result: .success(""), metric: nil, completion: completion)
            return
        }
        let config = run.config
        let transcriber = Transcribers.isLocal(TranscriptionSource(rawValue: config.source) ?? .server) ? local : remote
        let cleaner = llm
        let log = self.log
        let wavBytes = (try? FileManager.default.attributesOfItem(atPath: run.audioURL.path))?[.size] as? Int
        pipelineTask = Task { [weak self] in
            let result: Result<String, Error>
            var metric: RunMetric?
            do {
                try Task.checkCancellation()
                guard mode != .english || config.postprocessEnabled else { throw NativePipelineError.englishRequiresCleanup }
                onPhase(.transcribing)
                let whisperStart = Date()
                let raw = try await transcriber.transcribe(audioURL: run.audioURL, config: config)
                try Task.checkCancellation()
                let whisperMs = Int(Date().timeIntervalSince(whisperStart) * 1000)
                var text = raw
                var postprocessMs = 0
                if !raw.isEmpty, Self.usesLLM(mode), config.postprocessEnabled {
                    onPhase(.postprocessing)
                    let llmStart = Date()
                    do {
                        text = try await cleaner.clean(transcript: raw, config: config, translateTo: Self.translateTarget(mode))
                        try Task.checkCancellation()
                    } catch {
                        if Task.isCancelled || error is CancellationError { throw CancellationError() }
                        if mode == .english { throw NativePipelineError.englishTranslationFailed(error.localizedDescription) }
                        guard config.autoRawFallback else { throw error }
                        log("llm_cleanup_failed_fallback_raw \(error.localizedDescription)")
                        text = raw
                    }
                    postprocessMs = Int(Date().timeIntervalSince(llmStart) * 1000)
                }
                try Task.checkCancellation()
                let final = config.replacements.preview(text)
                metric = RunMetric(schema: 1, timestamp: ISO8601DateFormatter().string(from: Date()),
                                   runId: run.id.uuidString, mode: mode.rawValue, wavBytes: wavBytes,
                                   recordingMs: nil, whisperMs: whisperMs, whisperTextChars: raw.count,
                                   postprocessMs: postprocessMs > 0 ? postprocessMs : nil,
                                   outputChars: final.count, pasteStatus: nil)
                result = .success(final)
            } catch { result = .failure(error) }
            // Finalize even for empty results, errors and cancelled clients.
            try? FileManager.default.removeItem(at: run.audioURL)
            let finishedMetric = metric
            DispatchQueue.main.async { [weak self] in
                self?.finish(run: run, result: result, metric: finishedMetric, completion: completion)
            }
        }
    }

    private func finish(run: Run, result: Result<String, Error>, metric: RunMetric?,
                        completion: @escaping (Result<String, Error>) -> Void) {
        guard activeRun?.id == run.id else { return }
        activeRun = nil
        pipelineTask = nil
        if let metric { recordMetric(metric) }
        completion(result)
    }
}
