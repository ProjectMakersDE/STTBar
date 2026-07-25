import XCTest
@testable import STTBar

/// Exercises `DataFolderModel.cleanUp()`'s safety gate headlessly: the
/// injected `confirm` closure stands in for the blocking `NSAlert`, and
/// injected `runtime`/`logs` directories stand in for the real ones, so no
/// test touches the user's actual scratch files or pops a modal.
final class DataFolderModelTests: XCTestCase {
    private var root: URL!
    private var runtime: URL!
    private var logs: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DataFolderModelTests-\(UUID().uuidString)")
        runtime = root.appendingPathComponent("runtime")
        logs = root.appendingPathComponent("logs")
        for dir in [runtime!, logs!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String = "x", to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func makeModel(isIdle: @escaping () -> Bool,
                           confirm: @escaping () -> Bool = { true }) -> DataFolderModel {
        DataFolderModel(isIdle: isIdle, confirm: confirm, runtime: runtime, logs: logs)
    }

    /// The gate holds: a run in flight must refuse the cleanup and leave the
    /// button-disabling flag set, even though nothing was ever deleted.
    func testCleanUpRefusesWhenNotIdle() throws {
        let recording = runtime.appendingPathComponent("recording.wav")
        try write(to: recording)
        let model = makeModel(isIdle: { false })

        model.cleanUp()

        XCTAssertTrue(model.isBusy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.path))
    }

    /// Declining the confirmation alert must delete nothing.
    func testCleanUpRefusesWhenNotConfirmed() throws {
        let recording = runtime.appendingPathComponent("recording.wav")
        try write(to: recording)
        let model = makeModel(isIdle: { true }, confirm: { false })

        model.cleanUp()

        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.path))
    }

    /// With the gate open, only the allowlisted scratch files disappear;
    /// neighbouring files that merely share a directory are untouched.
    func testCleanUpRemovesOnlyAllowlistedFiles() throws {
        let recordingWav = runtime.appendingPathComponent("recording.wav")
        let eventsJsonl = runtime.appendingPathComponent("events.jsonl")
        let sttbarLog = logs.appendingPathComponent("sttbar.log")
        try write(to: recordingWav)
        try write(to: eventsJsonl)
        try write(to: sttbarLog)

        let envFile = runtime.appendingPathComponent(".env")
        let promptsFile = runtime.appendingPathComponent("prompts.json")
        let pidFile = runtime.appendingPathComponent("recording.pid")
        try write(to: envFile)
        try write(to: promptsFile)
        try write(to: pidFile)

        let model = makeModel(isIdle: { true }, confirm: { true })

        model.cleanUp()

        XCTAssertFalse(FileManager.default.fileExists(atPath: recordingWav.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: eventsJsonl.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sttbarLog.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: envFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: promptsFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pidFile.path))
    }

    /// `cleanUp()` re-checks `isIdle` at click time rather than trusting a
    /// stale snapshot: a closure that reports idle once (as `refresh()` would
    /// see on window open) and busy the second time (as a run that started
    /// meanwhile would leave it) must refuse the click.
    func testCleanUpRechecksIdleAtClickTime() throws {
        let recording = runtime.appendingPathComponent("recording.wav")
        try write(to: recording)
        var callCount = 0
        let isIdle: () -> Bool = {
            callCount += 1
            return callCount == 1
        }
        let model = makeModel(isIdle: isIdle)

        model.refresh() // first call: idle, as if the window had just opened
        XCTAssertFalse(model.isBusy)

        model.cleanUp() // second call: a run has since started; must refuse
        XCTAssertTrue(model.isBusy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.path))
    }
}
