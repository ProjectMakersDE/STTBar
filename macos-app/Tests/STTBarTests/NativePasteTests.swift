import XCTest
import CoreGraphics
@testable import STTBar

final class NativePasteTests: XCTestCase {
    func testHeldModifiersKeepsChordModifiers() {
        let flags: CGEventFlags = [.maskControl, .maskShift]
        XCTAssertEqual(NativePaste.heldModifiers(flags), [.maskControl, .maskShift])
    }

    func testHeldModifiersDropsCapsLockAndFn() {
        let flags: CGEventFlags = [.maskControl, .maskAlphaShift, .maskSecondaryFn]
        XCTAssertEqual(NativePaste.heldModifiers(flags), [.maskControl])
    }

    func testDescribeListsModifiersInStableOrder() {
        XCTAssertEqual(NativePaste.describe([.maskShift, .maskControl, .maskCommand]), "cmd+ctrl+shift")
    }

    func testDescribeEmptyIsNone() {
        XCTAssertEqual(NativePaste.describe([]), "none")
    }

    func testWaitReturnsImmediatelyWhenNothingHeld() {
        var reads = 0
        var slept = 0
        let remaining = NativePaste.waitForModifiersToClear(
            timeout: 1.0, pollInterval: 0.01,
            now: { 0 },
            currentFlags: { reads += 1; return [] },
            sleep: { _ in slept += 1 }
        )
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(slept, 0)
    }

    func testWaitPollsUntilModifiersRelease() {
        let sequence: [CGEventFlags] = [[.maskControl, .maskShift], [.maskControl], []]
        var reads = 0
        var t = 0.0
        var slept = 0
        let remaining = NativePaste.waitForModifiersToClear(
            timeout: 1.0, pollInterval: 0.01,
            now: { t },
            currentFlags: { let f = sequence[min(reads, sequence.count - 1)]; reads += 1; return f },
            sleep: { dt in slept += 1; t += dt }
        )
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(slept, 2)
    }

    func testWaitTimesOutWhileHeldWithoutHanging() {
        var t = 0.0
        let remaining = NativePaste.waitForModifiersToClear(
            timeout: 0.05, pollInterval: 0.01,
            now: { t },
            currentFlags: { [.maskControl, .maskShift] },
            sleep: { dt in t += dt }
        )
        XCTAssertEqual(remaining, [.maskControl, .maskShift])
    }

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
