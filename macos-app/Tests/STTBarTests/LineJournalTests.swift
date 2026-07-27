import XCTest
@testable import STTBar

final class LineJournalTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sttbar-journal-\(UUID().uuidString).jsonl")
    }

    func testTailReturnsWholeSmallFile() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try "a\nb\nc\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(LineJournal.tail(of: url), "a\nb\nc\n")
    }

    func testTailDropsPartialFirstLineWhenCapped() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try "0123456789\nsecond\nthird\n".write(to: url, atomically: true, encoding: .utf8)
        // A 10-byte window from the end starts inside "second"; the partial
        // line must be dropped so callers only ever see complete lines.
        XCTAssertEqual(LineJournal.tail(of: url, maxBytes: 10), "third\n")
    }

    func testTailOfMissingFileIsNil() {
        XCTAssertNil(LineJournal.tail(of: tempFile()))
    }

    private func lines(_ data: [Data]) -> [String] {
        data.map { String(decoding: $0, as: UTF8.self) }
    }

    func testTailLinesSplitsOnNewlineBytes() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try "a\nb\nc\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(lines(LineJournal.tailLines(of: url)), ["a", "b", "c"])
    }

    func testTailLinesDropsPartialFirstLineWhenCapped() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try "0123456789\nsecond\nthird\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(lines(LineJournal.tailLines(of: url, maxBytes: 10)), ["third"])
    }

    func testTailLinesOfMissingFileIsEmpty() {
        XCTAssertTrue(LineJournal.tailLines(of: tempFile()).isEmpty)
    }

    /// The byte split must not cut multi-byte scalars, which is the whole risk
    /// of replacing the grapheme-based `String.split`.
    func testTailLinesKeepsMultiByteScalars() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try "grüße\n😀\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(lines(LineJournal.tailLines(of: url)), ["grüße", "😀"])
    }

    func testAppendCreatesAndAppends() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        LineJournal.append("one\n", to: url)
        LineJournal.append("two\n", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "one\ntwo\n")
    }

    func testAppendTrimsOversizedFileToCompleteTailLines() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let line = String(repeating: "x", count: 99) + "\n" // 100 bytes per line
        try String(repeating: line, count: 50).write(to: url, atomically: true, encoding: .utf8)
        LineJournal.append("last\n", to: url, maxBytes: 1_000, keepBytes: 500)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertLessThanOrEqual(text.utf8.count, 500)
        XCTAssertTrue(text.hasSuffix("last\n"))
        // Every surviving line must be complete (a bare "x"-run or the marker).
        for l in text.split(separator: "\n") {
            XCTAssertTrue(l == "last" || l.count == 99, "unexpected partial line: \(l)")
        }
    }
}
