import XCTest
@testable import STTBar

final class NativePasteTests: XCTestCase {
    func testChunkingSplitsByUTF16Size() {
        let chunks = NativePaste.utf16Chunks("abcdef", size: 2)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], Array("ab".utf16))
        XCTAssertEqual(chunks[1], Array("cd".utf16))
        XCTAssertEqual(chunks[2], Array("ef".utf16))
    }

    func testChunkingEmptyTextYieldsNoChunks() {
        XCTAssertTrue(NativePaste.utf16Chunks("", size: 20).isEmpty)
    }

    func testChunkingShorterThanSizeIsSingleChunk() {
        let chunks = NativePaste.utf16Chunks("hi", size: 20)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], Array("hi".utf16))
    }
}
