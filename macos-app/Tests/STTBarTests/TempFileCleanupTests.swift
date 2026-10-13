import XCTest
@testable import STTBar

final class TempFileCleanupTests: XCTestCase {
    private var root: URL!
    private var config: URL!
    private var runtime: URL!
    private var logs: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TempFileCleanupTests-\(UUID().uuidString)")
        config = root.appendingPathComponent("Application Support/STTBar")
        runtime = config.appendingPathComponent("runtime")
        logs = root.appendingPathComponent("Logs/STTBar")
        for dir in [config!, runtime!, logs!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ byteCount: Int, to url: URL) throws {
        try Data(repeating: 0x41, count: byteCount).write(to: url)
    }

    func testRemovesOnlyDisposableFiles() throws {
        try write(100, to: runtime.appendingPathComponent("recording.wav"))
        try write(10, to: runtime.appendingPathComponent("events.jsonl"))
        try write(10, to: runtime.appendingPathComponent("metrics.jsonl"))
        try write(10, to: runtime.appendingPathComponent("status.json"))
        try write(5, to: runtime.appendingPathComponent("phase"))
        try write(15, to: runtime.appendingPathComponent("last-transcript.txt"))
        try write(50, to: logs.appendingPathComponent("sttbar.log"))

        let survivors = [
            runtime.appendingPathComponent("recording.pid"),
            runtime.appendingPathComponent("recording.lock"),
            config.appendingPathComponent(".env"),
            config.appendingPathComponent("prompts.json"),
            config.appendingPathComponent("active-prompt.txt"),
            config.appendingPathComponent("stt-replacements.tsv"),
            config.appendingPathComponent("transcript-history.json"),
            config.appendingPathComponent(".env.backup-1782398573"),
        ]
        for url in survivors { try write(8, to: url) }

        let result = TempFileCleanup.run(runtime: runtime, logs: logs)

        XCTAssertEqual(result, TempFileCleanup.Result(removedFiles: 7, freedBytes: 200))
        for name in TempFileCleanup.runtimeFileNames {
            XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.appendingPathComponent(name).path), name)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: logs.appendingPathComponent("sttbar.log").path))
        for url in survivors {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
        }
    }

    func testEmptyDirectoriesAreANoOp() {
        let result = TempFileCleanup.run(runtime: runtime, logs: logs)
        XCTAssertEqual(result, TempFileCleanup.Result(removedFiles: 0, freedBytes: 0))
    }

    func testStartupRemovesOnlyUniqueNativeRecordingFiles() throws {
        let recording = runtime.appendingPathComponent("recording-\(UUID().uuidString).wav")
        try write(42, to: recording)
        let survivors = ["recording.wav", "recording-not-a-uuid.wav", "transcript-history.json"]
        for name in survivors { try write(5, to: runtime.appendingPathComponent(name)) }
        let nested = runtime.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let nestedFile = nested.appendingPathComponent("recording-\(UUID().uuidString).wav")
        try write(7, to: nestedFile)

        XCTAssertEqual(TempFileCleanup.removeOrphanedRecordings(runtime: runtime),
                       .init(removedFiles: 1, freedBytes: 42))
        for name in survivors { XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.appendingPathComponent(name).path)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedFile.path))
    }

    func testStartupDoesNotFollowRecordingSymlinksOrDeleteDirectories() throws {
        let external = config.appendingPathComponent("keep.wav")
        try write(10, to: external)
        let link = runtime.appendingPathComponent("recording-\(UUID().uuidString).wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        let directory = runtime.appendingPathComponent("recording-\(UUID().uuidString).wav")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertEqual(TempFileCleanup.removeOrphanedRecordings(runtime: runtime),
                       .init(removedFiles: 0, freedBytes: 0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDefaultContainerMigrationRemovesOldFixedRecording() throws {
        let oldRecording = runtime.appendingPathComponent("recording.wav")
        try write(12, to: oldRecording)
        XCTAssertEqual(TempFileCleanup.removeOrphanedRecordings(runtime: runtime, includeLegacy: true),
                       .init(removedFiles: 1, freedBytes: 12))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldRecording.path))
    }

    func testDoesNotRemoveADirectoryNamedLikeATempFile() throws {
        let trap = runtime.appendingPathComponent("phase")
        try FileManager.default.createDirectory(at: trap, withIntermediateDirectories: true)
        try write(4, to: trap.appendingPathComponent("inside.txt"))

        let result = TempFileCleanup.run(runtime: runtime, logs: logs)

        XCTAssertEqual(result, TempFileCleanup.Result(removedFiles: 0, freedBytes: 0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trap.path))
    }

    func testNoRemovableURLPointsAtTheConfigDirectory() {
        for url in TempFileCleanup.removableURLs(runtime: runtime, logs: logs) {
            XCTAssertNotEqual(url.deletingLastPathComponent().standardizedFileURL,
                              config.standardizedFileURL,
                              "\(url.lastPathComponent) darf nicht im Konfigurations-Ordner liegen")
        }
    }
}
