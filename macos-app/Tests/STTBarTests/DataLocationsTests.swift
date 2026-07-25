import XCTest
@testable import STTBar

final class DataLocationsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DataLocationsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ byteCount: Int, to url: URL) throws {
        try Data(repeating: 0x41, count: byteCount).write(to: url)
    }

    func testSumsFilesRecursively() throws {
        try write(10, to: root.appendingPathComponent("a.txt"))
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try write(20, to: sub.appendingPathComponent("b.txt"))
        XCTAssertEqual(DirectorySize.bytes(of: root), 30)
    }

    func testCountsDotFiles() throws {
        // `.env` ist die wichtigste Datei im Konfigurations-Ordner; ein
        // Hidden-File-Skip würde sie stillschweigend aus der Größe werfen.
        try write(5, to: root.appendingPathComponent(".env"))
        XCTAssertEqual(DirectorySize.bytes(of: root), 5)
    }

    func testExcludesNestedDirectory() throws {
        try write(10, to: root.appendingPathComponent("a.txt"))
        let runtime = root.appendingPathComponent("runtime")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        try write(20, to: runtime.appendingPathComponent("recording.wav"))
        XCTAssertEqual(DirectorySize.bytes(of: root, excluding: runtime), 10)
    }

    func testExcludingDoesNotMatchSiblingPrefix() throws {
        // "runtime-old" beginnt mit "runtime"; ein blankes hasPrefix würde den
        // Nachbarordner fälschlich mit ausklammern.
        let runtime = root.appendingPathComponent("runtime")
        let sibling = root.appendingPathComponent("runtime-old")
        for dir in [runtime, sibling] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try write(20, to: runtime.appendingPathComponent("recording.wav"))
        try write(7, to: sibling.appendingPathComponent("keep.txt"))
        XCTAssertEqual(DirectorySize.bytes(of: root, excluding: runtime), 7)
    }

    func testMissingDirectoryIsZero() {
        XCTAssertEqual(DirectorySize.bytes(of: root.appendingPathComponent("nope")), 0)
    }

    func testRuntimeLocationIsInsideConfigLocation() throws {
        // Der Größen-Ausschluss lohnt sich nur, solange diese Verschachtelung gilt.
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless((env["STT_INSTALL_DIR"] ?? "").isEmpty && (env["STT_RUNTIME_DIR"] ?? "").isEmpty,
                          "Pfad-Overrides heben die hier geprüfte Verschachtelung auf")
        XCTAssertTrue(DataLocation.runtime.url.path.hasPrefix(DataLocation.config.url.path + "/"))
    }

    func testEveryLocationHasATitle() {
        for location in DataLocation.allCases {
            XCTAssertFalse(location.title.isEmpty, location.rawValue)
            XCTAssertFalse(location.detail.isEmpty, location.rawValue)
        }
    }
}
