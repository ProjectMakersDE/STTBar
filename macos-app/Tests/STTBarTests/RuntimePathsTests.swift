import XCTest
@testable import STTBar

final class RuntimePathsTests: XCTestCase {
    func testDirectoryIsUnderApplicationSupportNotTmp() {
        // Sandbox containers expose Application Support under the container's Data
        // dir; the runtime scratch must live there, never in /tmp.
        let original = ProcessInfo.processInfo.environment["STT_RUNTIME_DIR"]
        if original != nil { setenv("STT_RUNTIME_DIR", "", 1) }
        defer { if let original { setenv("STT_RUNTIME_DIR", original, 1) } }

        let path = RuntimePaths.directory.path
        XCTAssertTrue(path.contains("Application Support"),
                      "runtime dir must live in Application Support, got \(path)")
        XCTAssertFalse(path.hasPrefix("/tmp"), "runtime dir must not be under /tmp, got \(path)")
        XCTAssertFalse(path.hasPrefix("/private/tmp"), "runtime dir must not be under /tmp, got \(path)")
    }

    func testDerivedFilesLiveInsideDirectory() {
        let dir = RuntimePaths.directory.path
        XCTAssertTrue(RuntimePaths.resultFile.path.hasPrefix(dir))
        XCTAssertTrue(RuntimePaths.phaseFile.path.hasPrefix(dir))
    }
}
