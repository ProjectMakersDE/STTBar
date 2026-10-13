import XCTest
import CoreGraphics
import AppKit
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

    func testChunkingKeepsSurrogatePairsIntactAtBoundary() {
        let text = String(repeating: "a", count: 19) + "😀Z"
        let chunks = NativePaste.utf16Chunks(text, size: 20)
        XCTAssertEqual(chunks.map { String(decoding: $0, as: UTF16.self) }.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(chunks[0].count, 19)
    }

    func testChunkingSizeOneStillKeepsEmojiIntact() {
        let text = "a😀b"
        let chunks = NativePaste.utf16Chunks(text, size: 1)
        XCTAssertEqual(chunks.map { String(decoding: $0, as: UTF16.self) }.joined(), text)
    }
}

private final class SyntheticClipboard: ClipboardAccess {
    var changeCount = 0
    var items: [[NSPasteboard.PasteboardType: Data]] = []
    var onRead: (() -> Void)?
    func contents() -> [[NSPasteboard.PasteboardType: Data]] {
        let previous = items
        onRead?()
        return previous
    }
    @discardableResult func replaceContents(with items: [[NSPasteboard.PasteboardType: Data]]) -> Int {
        self.items = items
        changeCount += 1
        return changeCount
    }
}

final class NativeClipboardTests: XCTestCase {
    func testCancelledPasteStopsBeforePermissionOrClipboardAccess() {
        var completed = false
        NativePaste.copyAndPaste("cancelled", sensitive: true, shouldContinue: { false }) { result in
            guard case .clipboardOnly = result else { return XCTFail("Expected cancellation") }
            completed = true
        }
        XCTAssertTrue(completed)
    }

    func testExplicitSensitiveCopyIncludesConcealedMarker() {
        let clipboard = SyntheticClipboard()
        NativePaste.copyToClipboard("private", sensitive: true, clipboard: clipboard)
        XCTAssertEqual(clipboard.items.first?[.string], Data("private".utf8))
        XCTAssertNotNil(clipboard.items.first?[NativePaste.concealedType])
    }

    func testClipboardFallbackRestoresAllFormatsAndItems() {
        let clipboard = SyntheticClipboard()
        let original: [[NSPasteboard.PasteboardType: Data]] = [
            [.string: Data("old".utf8), .rtf: Data([1, 2]), NativePaste.concealedType: Data()],
            [.png: Data([3, 4]), .fileURL: Data("file:///synthetic".utf8)]
        ]
        clipboard.items = original
        var restore: (() -> Void)?
        _ = NativePaste.pasteViaClipboard("new", sensitive: false, clipboard: clipboard,
                                          postPaste: { true }, scheduleRestore: { _, action in restore = action })
        XCTAssertEqual(clipboard.items.first?[.string], Data("new".utf8))
        restore?()
        XCTAssertEqual(clipboard.items, original)
    }

    func testClipboardFallbackDoesNotOverwriteNewerCopy() {
        let clipboard = SyntheticClipboard()
        clipboard.items = [[.string: Data("old".utf8)]]
        var restore: (() -> Void)?
        _ = NativePaste.pasteViaClipboard("dictation", sensitive: false, clipboard: clipboard,
                                          postPaste: { true }, scheduleRestore: { _, action in restore = action })
        clipboard.replaceContents(with: [[.string: Data("newer user copy".utf8)]])
        restore?()
        XCTAssertEqual(clipboard.items.first?[.string], Data("newer user copy".utf8))
    }

    func testClipboardChangeDuringSnapshotIsNotOverwritten() {
        let clipboard = SyntheticClipboard()
        clipboard.items = [[.string: Data("old".utf8)]]
        clipboard.onRead = { clipboard.replaceContents(with: [[.string: Data("newer".utf8)]]) }
        var posted = false, scheduled = false
        let result = NativePaste.pasteViaClipboard("dictation", sensitive: false, clipboard: clipboard,
                                                   postPaste: { posted = true; return true },
                                                   scheduleRestore: { _, _ in scheduled = true })
        guard case .clipboardOnly = result else { return XCTFail("Expected changed snapshot") }
        XCTAssertFalse(posted)
        XCTAssertFalse(scheduled)
        XCTAssertEqual(clipboard.items.first?[.string], Data("newer".utf8))
    }

    func testClipboardFallbackRestoresPreviouslyEmptyClipboard() {
        let clipboard = SyntheticClipboard()
        var restore: (() -> Void)?
        _ = NativePaste.pasteViaClipboard("dictation", sensitive: false, clipboard: clipboard,
                                          postPaste: { true }, scheduleRestore: { _, action in restore = action })
        restore?()
        XCTAssertTrue(clipboard.items.isEmpty)
    }

    func testFailedPasteKeepsSensitiveManualFallback() {
        let clipboard = SyntheticClipboard()
        var scheduled = false
        let result = NativePaste.pasteViaClipboard("private", sensitive: true, clipboard: clipboard,
                                                   postPaste: { false }, scheduleRestore: { _, _ in scheduled = true })
        guard case .clipboardOnly = result else { return XCTFail("Expected manual fallback") }
        XCTAssertFalse(scheduled)
        XCTAssertNotNil(clipboard.items.first?[NativePaste.concealedType])
    }
}
