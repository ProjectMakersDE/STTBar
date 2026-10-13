import XCTest
@testable import STTBar

private final class SyntheticRecorder: AudioRecording {
    var isRecording = false
    var outputURL: URL?
    var failStart = false
    func start(outputURL: URL, input: AudioInputResolution) throws {
        self.outputURL = outputURL
        try Data("synthetic audio".utf8).write(to: outputURL)
        if failStart { throw NSError(domain: "SyntheticStart", code: 1) }
        isRecording = true
    }
    func stop() -> URL? { isRecording = false; return outputURL }
    func cancel() { isRecording = false }
}

private struct SyntheticTranscriber: Transcriber {
    var action: (URL, TranscriptionConfig) async throws -> String
    func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String {
        try await action(audioURL, config)
    }
}

private struct SyntheticCleaner: TranscriptCleaning {
    var action: (String) async throws -> String
    func clean(transcript: String, config: TranscriptionConfig, translateTo: String?) async throws -> String {
        try await action(transcript)
    }
}

final class NativeBackendLifecycleTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("sttbar-backend-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func config() -> TranscriptionConfig {
        TranscriptionConfig(whisperURL: "https://synthetic.invalid", whisperModel: "m", language: "de",
                            postprocessEnabled: false, provider: "openai", lmStudioURL: "https://synthetic.invalid",
                            llmModel: "m", promptBody: "", transcribeTimeout: 1, postprocessTimeout: 1,
                            temperature: 0, reasoning: "off", replacements: ReplacementStore(directory: directory),
                            source: "server", localModel: "", sensitiveMode: true)
    }

    private func backend(config: @escaping () -> TranscriptionConfig,
                         recorder: SyntheticRecorder,
                         transcribe: @escaping (URL, TranscriptionConfig) async throws -> String,
                         clean: @escaping (String) async throws -> String = { $0 }) -> NativeBackend {
        let directory = directory!
        let transcriber = SyntheticTranscriber(action: transcribe)
        return NativeBackend(config: config, recorder: recorder, remote: transcriber, local: transcriber,
                             llm: SyntheticCleaner(action: clean),
                             resolveInput: { _ in (.systemDefault, "synthetic") },
                             recordingURL: { directory.appendingPathComponent("recording-\(UUID().uuidString).wav") },
                             recordMetric: { _ in }, sensitiveMode: { false }, log: { _ in })
    }

    private func finish(_ backend: NativeBackend, mode: SttMode = .raw) async -> Result<String, Error> {
        await withCheckedContinuation { continuation in
            backend.stop(mode: mode, onPhase: { _ in }, completion: { continuation.resume(returning: $0) })
        }
    }

    func testSensitiveSuccessDeletesItsAudioBeforeCompletion() async throws {
        let recorder = SyntheticRecorder(), cfg = config()
        let backend = backend(config: { cfg }, recorder: recorder, transcribe: { _, _ in "Hello" })
        try backend.start(mode: .raw)
        let audio = try XCTUnwrap(backend.recordingURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        let result = await finish(backend)
        XCTAssertEqual(try result.get(), "Hello")
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }

    func testEmptyAndFailedTranscriptionDeleteAudio() async throws {
        for fails in [false, true] {
            let recorder = SyntheticRecorder(), cfg = config()
            let backend = backend(config: { cfg }, recorder: recorder, transcribe: { _, _ in
                if fails { throw NSError(domain: "SyntheticWhisper", code: 1) }
                return ""
            })
            try backend.start(mode: .raw)
            let audio = try XCTUnwrap(backend.recordingURL)
            let result = await finish(backend)
            if !fails { XCTAssertEqual(try result.get(), "") }
            else { XCTAssertThrowsError(try result.get()) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        }
    }

    func testStartFailureAndRecordingCancelDeleteAudio() throws {
        let recorder = SyntheticRecorder(), cfg = config()
        let backend = backend(config: { cfg }, recorder: recorder, transcribe: { _, _ in "unused" })
        recorder.failStart = true
        XCTAssertThrowsError(try backend.start(mode: .raw))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(recorder.outputURL).path))
        recorder.failStart = false
        try backend.start(mode: .raw)
        let audio = try XCTUnwrap(backend.recordingURL)
        backend.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertNil(backend.recordingURL)
    }

    func testPrivacyAndConfigurationAreSnapshottedAtStart() async throws {
        var cfg = config()
        let recorder = SyntheticRecorder()
        let backend = backend(config: { cfg }, recorder: recorder, transcribe: { _, seen in
            XCTAssertTrue(seen.sensitiveMode)
            XCTAssertEqual(seen.language, "de")
            return "Hello"
        })
        try backend.start(mode: .raw)
        XCTAssertTrue(backend.isSensitiveRun)
        cfg.sensitiveMode = false
        cfg.language = "en"
        _ = await finish(backend)
    }

    func testRawFallbackHonorsSwitchAndEnglishNeverFallsBack() async throws {
        for (mode, fallback, succeeds) in [(SttMode.full, true, true), (.full, false, false), (.english, true, false)] {
            var cfg = config()
            cfg.postprocessEnabled = true
            cfg.autoRawFallback = fallback
            let recorder = SyntheticRecorder()
            let backend = backend(config: { cfg }, recorder: recorder, transcribe: { _, _ in "Guten Morgen" },
                                  clean: { _ in throw NSError(domain: "SyntheticLLM", code: 1) })
            try backend.start(mode: mode)
            let audio = try XCTUnwrap(backend.recordingURL)
            let result = await finish(backend, mode: mode)
            if succeeds { XCTAssertEqual(try result.get(), "Guten Morgen") }
            else { XCTAssertThrowsError(try result.get()) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        }
    }

    func testEnglishWithoutCleanupFailsClearlyAndDeletesAudio() async throws {
        let cfg = config(), recorder = SyntheticRecorder()
        let backend = backend(config: { cfg }, recorder: recorder, transcribe: { _, _ in
            XCTFail("No translation path must be rejected before transcription")
            return "Guten Morgen"
        })
        try backend.start(mode: .english)
        let audio = try XCTUnwrap(backend.recordingURL)
        let result = await finish(backend, mode: .english)
        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0.localizedDescription.contains("LLM")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }

    func testCancelledPipelineCannotCompleteOrDeleteNewRun() async throws {
        let cfg = config(), recorder = SyntheticRecorder()
        let entered = expectation(description: "first transcription entered")
        let late = expectation(description: "cancelled pipeline completed")
        late.isInverted = true
        var resumeFirst: CheckedContinuation<String, Never>?
        let backend = backend(config: { cfg }, recorder: recorder, transcribe: { _, _ in
            await withCheckedContinuation { continuation in
                resumeFirst = continuation
                entered.fulfill()
            }
        })
        try backend.start(mode: .raw)
        let first = try XCTUnwrap(backend.recordingURL)
        backend.stop(mode: .raw, onPhase: { _ in }, completion: { _ in late.fulfill() })
        await fulfillment(of: [entered], timeout: 2)
        backend.cancel()
        try backend.start(mode: .raw)
        let second = try XCTUnwrap(backend.recordingURL)
        XCTAssertNotEqual(first, second)
        resumeFirst?.resume(returning: "stale")
        await fulfillment(of: [late], timeout: 0.15)
        XCTAssertTrue(backend.isRecording)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        backend.cancel()
    }
}

final class LocalDecodingOptionsTests: XCTestCase {
    func testCompleteCacheOpensWithoutDownloadAndMissingCacheCanDownload() {
        let base = URL(fileURLWithPath: "/synthetic/model-cache"), cached = base.appendingPathComponent("selected-model")
        let cachedConfig = LocalTranscriber.whisperKitConfig(model: "small", cachedFolder: cached, downloadBase: base)
        XCTAssertEqual(cachedConfig.model, "small")
        XCTAssertEqual(cachedConfig.modelFolder, cached.path)
        XCTAssertEqual(cachedConfig.load, true)
        XCTAssertFalse(cachedConfig.download)
        let freshConfig = LocalTranscriber.whisperKitConfig(model: "small", cachedFolder: nil, downloadBase: base)
        XCTAssertNil(freshConfig.modelFolder)
        XCTAssertEqual(freshConfig.load, true)
        XCTAssertTrue(freshConfig.download)
    }

    func testDistilShorthandUsesSameCanonicalModelForCacheAndDownload() {
        XCTAssertEqual(LocalTranscriber.requestedModelName(" distil-large-v3 "), "distil-whisper_distil-large-v3")
        XCTAssertEqual(LocalTranscriber.requestedModelName("distil-whisper_distil-large-v3"), "distil-whisper_distil-large-v3")
        XCTAssertEqual(OnboardingReadiness.requestedLocalModel("distil-large-v3"), "distil-whisper_distil-large-v3")
    }

    func testAutomaticSelectsParakeetAndNamesPickTheirEngine() {
        XCTAssertEqual(LocalTranscriber.requestedModelName("  "), LocalModels.parakeetUltra)
        XCTAssertEqual(OnboardingReadiness.requestedLocalModel(""), LocalModels.parakeetUltra)
        XCTAssertEqual(LocalModels.engine(for: LocalModels.parakeetUltra), .parakeet(.ultra))
        XCTAssertEqual(LocalModels.engine(for: LocalModels.parakeetV3), .parakeet(.v3))
        XCTAssertEqual(LocalModels.engine(for: "large-v3-v20240930_626MB"), .whisper)
    }

    func testParakeetLanguageHintOnlyForKnownCodes() {
        XCTAssertEqual(LocalTranscriber.parakeetLanguage(" DE "), .german)
        XCTAssertNil(LocalTranscriber.parakeetLanguage("auto"))
        XCTAssertNil(LocalTranscriber.parakeetLanguage(""))
        XCTAssertNil(LocalTranscriber.parakeetLanguage("xx"))
    }

    /// File names checked against FluidAudio 0.17.7 `AsrModels.modelsExist`
    /// and a real Ultra download (2026-10-14).
    func testParakeetCacheIsReadyOnlyWhenComplete() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("sttbar-parakeet-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let folder = LocalModels.parakeetDirectory(.ultra, in: base)
        let files = ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc"]
        for name in files {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        XCTAssertNil(OnboardingReadiness.cachedLocalModelFolder(LocalModels.parakeetUltra, in: base))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("parakeet_vocab.json"))
        XCTAssertEqual(OnboardingReadiness.cachedLocalModelFolder(LocalModels.parakeetUltra, in: base), folder)
        XCTAssertNil(OnboardingReadiness.cachedLocalModelFolder(LocalModels.parakeetV3, in: base))
    }

    func testConfiguredLanguageAndAutoReachDecoder() {
        let german = LocalTranscriber.decodingOptions(language: " DE ")
        XCTAssertEqual(german.language, "de")
        XCTAssertFalse(german.detectLanguage)
        for language in ["auto", " AUTO ", ""] {
            let options = LocalTranscriber.decodingOptions(language: language)
            XCTAssertNil(options.language)
            XCTAssertTrue(options.detectLanguage)
        }
    }
}
