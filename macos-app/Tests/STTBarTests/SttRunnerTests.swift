import XCTest
@testable import STTBar

private final class MockBackend: TranscriptionBackend {
    private(set) var isRecording = false
    private(set) var startedModes: [SttMode] = []
    private(set) var stoppedModes: [SttMode] = []
    private(set) var cancelCount = 0
    var stopCompletion: ((Result<String, Error>) -> Void)?
    var stopOnPhase: ((TranscriptionPhase) -> Void)?

    func start(mode: SttMode) throws {
        startedModes.append(mode)
        isRecording = true
    }

    func stop(mode: SttMode,
              onPhase: @escaping (TranscriptionPhase) -> Void,
              completion: @escaping (Result<String, Error>) -> Void) {
        stoppedModes.append(mode)
        isRecording = false
        stopOnPhase = onPhase
        stopCompletion = completion
    }

    func cancel() {
        cancelCount += 1
        isRecording = false
    }
}

final class SttRunnerTests: XCTestCase {
    private func drainMainQueue(_ seconds: TimeInterval = 0.1) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Waits out the RecordingToggle debounce between two deliberate triggers.
    private func waitOutDebounce() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    }

    // Cancelling while a transcription is still in flight must invalidate its
    // completion: the late result used to paste stale text and clobber state.
    func testStaleCompletionAfterCancelIsDropped() {
        let backend = MockBackend()
        let runner = SttRunner(backend: backend)
        var transcripts: [String] = []
        runner.onTranscript = { text, _, _ in transcripts.append(text) }

        runner.trigger(mode: .raw)
        waitOutDebounce()
        runner.trigger(mode: .raw)          // stop -> completion pending
        XCTAssertEqual(runner.state, .whisper)
        runner.cancelRecording()
        XCTAssertEqual(runner.state, .idle)

        backend.stopCompletion?(.success("STALE"))
        drainMainQueue()

        XCTAssertEqual(transcripts, [])
        XCTAssertEqual(runner.state, .idle)
    }

    // A completion that arrives without an intervening cancel still lands.
    func testLiveCompletionStillDelivers() {
        let backend = MockBackend()
        let runner = SttRunner(backend: backend)
        var transcripts: [String] = []
        runner.onTranscript = { text, _, _ in transcripts.append(text) }

        runner.trigger(mode: .raw)
        waitOutDebounce()
        runner.trigger(mode: .raw)
        backend.stopCompletion?(.success(""))   // empty settles quietly, no paste
        drainMainQueue()

        XCTAssertEqual(runner.state, .idle)
        XCTAssertEqual(transcripts, [])         // empty text never reports

        waitOutDebounce()
        runner.trigger(mode: .raw)
        XCTAssertTrue(runner.isRecording)
    }

    // The max-duration watchdog must hand the audio to transcription instead
    // of destroying the recording.
    func testStopAndTranscribeStopsIntoWhisperPhase() {
        let backend = MockBackend()
        let runner = SttRunner(backend: backend)

        runner.trigger(mode: .english)
        XCTAssertTrue(runner.isRecording)

        runner.stopAndTranscribe()

        XCTAssertEqual(backend.stoppedModes, [.english])
        XCTAssertEqual(backend.cancelCount, 0)
        XCTAssertEqual(runner.state, .whisper)
    }

    func testStopAndTranscribeIsNoOpWhenIdle() {
        let backend = MockBackend()
        let runner = SttRunner(backend: backend)
        runner.stopAndTranscribe()
        XCTAssertTrue(backend.stoppedModes.isEmpty)
        XCTAssertEqual(runner.state, .idle)
    }

    // The backend's post-processing phase must surface as .llm so the HUD
    // shows the LLM/sparkles segment during cleanup.
    func testPostprocessingPhaseSurfacesAsLLM() {
        let backend = MockBackend()
        let runner = SttRunner(backend: backend)
        runner.trigger(mode: .full)
        waitOutDebounce()
        runner.trigger(mode: .full)          // stop -> .whisper
        XCTAssertEqual(runner.state, .whisper)

        backend.stopOnPhase?(.transcribing)
        drainMainQueue()
        XCTAssertEqual(runner.state, .whisper)

        backend.stopOnPhase?(.postprocessing)
        drainMainQueue()
        XCTAssertEqual(runner.state, .llm)
    }

    // A non-empty transcript is delivered through the now-async paste path.
    // (Accessibility is not granted to the test binary, so paste settles as
    // clipboard-only, but onTranscript must still fire with the text.)
    func testNonEmptyTranscriptIsDeliveredThroughAsyncPaste() {
        let backend = MockBackend()
        let runner = SttRunner(backend: backend)
        var got: [String] = []
        runner.onTranscript = { text, _, _ in got.append(text) }

        runner.trigger(mode: .raw)
        waitOutDebounce()
        runner.trigger(mode: .raw)
        backend.stopCompletion?(.success("HELLO"))
        drainMainQueue(0.3)

        XCTAssertEqual(got, ["HELLO"])
    }
}

final class StatusStoreMetricsTests: XCTestCase {
    func testAppendRunMetricRoundTrips() {
        let metric = RunMetric(schema: 1, timestamp: "2026-07-16T00:00:00Z", runId: nil,
                               mode: "full", wavBytes: 1000, recordingMs: nil,
                               whisperMs: 1200, whisperTextChars: 42,
                               postprocessMs: 800, outputChars: 40, pasteStatus: nil)
        StatusStore.appendRunMetric(metric)
        let read = StatusStore.readMetrics(limit: 1).first
        XCTAssertEqual(read?.mode, "full")
        XCTAssertEqual(read?.whisperMs, 1200)
        XCTAssertEqual(read?.postprocessMs, 800)
        XCTAssertEqual(read?.outputChars, 40)
    }
}
