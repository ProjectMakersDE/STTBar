import XCTest
@testable import STTBar

final class EnvStoreTests: XCTestCase {
    private func temp(_ contents: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-\(UUID().uuidString)")
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testReadsQuotedAndUnquotedValues() throws {
        let url = temp("# c\nSTT_MODEL=\"foo\"\nSTT_LANGUAGE=de\n")
        let store = try EnvStore(url: url)
        XCTAssertEqual(store.value("STT_MODEL"), "foo")
        XCTAssertEqual(store.value("STT_LANGUAGE"), "de")
    }

    func testUpdatePreservesCommentsAndUnknownKeys() throws {
        let url = temp("# header\nSTT_MODEL=\"old\"\nOTHER=keep\n")
        var store = try EnvStore(url: url)
        store.set("STT_MODEL", "new")
        try store.save()
        let out = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(out.contains("# header"))
        XCTAssertTrue(out.contains("OTHER=keep"))
        XCTAssertTrue(out.contains("STT_MODEL=\"new\""))
        XCTAssertFalse(out.contains("old"))
    }

    func testSetUnknownKeyAppends() throws {
        let url = temp("STT_MODEL=x\n")
        var store = try EnvStore(url: url)
        store.set("STT_POSTPROCESS_PROMPT_FILE", "/tmp/p.txt")
        try store.save()
        let out = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(out.contains("STT_POSTPROCESS_PROMPT_FILE=\"/tmp/p.txt\""))
    }

    func testEscapesShellSensitiveCharacters() throws {
        let url = temp("")
        var store = try EnvStore(url: url)
        store.set("STT_POSTPROCESS_MODEL", "foo\"bar$baz`qux")
        try store.save()
        let reloaded = try EnvStore(url: url)
        XCTAssertEqual(reloaded.value("STT_POSTPROCESS_MODEL"), #"foo"bar$baz`qux"#)
        let out = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(out.contains(#"foo\"bar\$baz\`qux"#))
    }
}
