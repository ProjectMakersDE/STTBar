import XCTest
@testable import STTBar

final class HudLayoutTests: XCTestCase {
    private func full(_ scale: CGFloat) -> HudLayout {
        HudLayout(scale: scale, showIcon: true, showWaveform: true, showTimer: true)
    }

    func testPanelSizeScalesLinearlyWithScale() {
        let a = full(1)
        let b = full(2)
        XCTAssertEqual(b.panelSize.width, a.panelSize.width * 2, accuracy: 0.001)
        XCTAssertEqual(b.panelSize.height, a.panelSize.height * 2, accuracy: 0.001)
    }

    func testBaseGeometryIsIndependentOfScale() {
        let a = full(1)
        let b = full(1.7)
        XCTAssertEqual(a.baseWidth, b.baseWidth, accuracy: 0.001)
        XCTAssertEqual(a.contentLeft, b.contentLeft, accuracy: 0.001)
        XCTAssertEqual(a.visualCenterY, b.visualCenterY, accuracy: 0.001)
    }

    func testHidingIconRemovesIconRectAndRecentersContent() {
        let withIcon = HudLayout(scale: 1, showIcon: true, showWaveform: true, showTimer: true)
        let noIcon = HudLayout(scale: 1, showIcon: false, showWaveform: true, showTimer: true)
        XCTAssertNotNil(withIcon.iconRect)
        XCTAssertNil(noIcon.iconRect)
        XCTAssertLessThan(noIcon.contentLeft, withIcon.contentLeft)
        XCTAssertLessThan(noIcon.baseWidth, withIcon.baseWidth)
    }

    func testContentRightLeavesRightMargin() {
        let l = full(1)
        XCTAssertEqual(l.contentRight, l.baseWidth - 12, accuracy: 0.001)
    }

    func testHidingTimerShrinksHeightAndCentersVertically() {
        let withTimer = HudLayout(scale: 1, showIcon: true, showWaveform: true, showTimer: true)
        let noTimer = HudLayout(scale: 1, showIcon: true, showWaveform: true, showTimer: false)
        XCTAssertLessThan(noTimer.baseHeight, withTimer.baseHeight)
        XCTAssertEqual(noTimer.visualCenterY, noTimer.baseHeight / 2, accuracy: 0.001)
    }

    func testWaveformAndTimerBothOffCollapsesContentAreaAndPanelWidth() {
        let full = HudLayout(scale: 1, showIcon: true, showWaveform: true, showTimer: true)
        let collapsed = HudLayout(scale: 1, showIcon: true, showWaveform: false, showTimer: false)
        XCTAssertLessThan(collapsed.contentAreaWidth, full.contentAreaWidth)
        XCTAssertLessThan(collapsed.baseWidth, full.baseWidth)
    }

    func testVisibleTimerKeepsFullWidthWhenWaveformOff() {
        // The combined whisper/llm timer needs the full width; hiding only the
        // waveform must not shrink the content area below it (would overflow).
        let full = HudLayout(scale: 1, showIcon: true, showWaveform: true, showTimer: true)
        let timerOnly = HudLayout(scale: 1, showIcon: true, showWaveform: false, showTimer: true)
        XCTAssertEqual(timerOnly.contentAreaWidth, full.contentAreaWidth, accuracy: 0.001)
    }
}

final class HudAnchorOffsetTests: XCTestCase {
    private let size = NSSize(width: 200, height: 60)
    private let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)

    func testZeroOffsetMatchesBaseOrigin() {
        let base = HudAnchor.topRight.origin(for: size, in: screen)
        let zero = HudAnchor.topRight.origin(for: size, in: screen, offset: .zero)
        XCTAssertEqual(zero.x, base.x, accuracy: 0.001)
        XCTAssertEqual(zero.y, base.y, accuracy: 0.001)
    }

    func testOffsetShiftsOriginByExactAmount() {
        let base = HudAnchor.topCenter.origin(for: size, in: screen)
        let shifted = HudAnchor.topCenter.origin(for: size, in: screen, offset: CGSize(width: 30, height: -12))
        XCTAssertEqual(shifted.x, base.x + 30, accuracy: 0.001)
        XCTAssertEqual(shifted.y, base.y - 12, accuracy: 0.001)
    }
}

final class ScreenPickerTests: XCTestCase {
    func testReturnsIndexOfRectContainingPoint() {
        let rects = [CGRect(x: 0, y: 0, width: 100, height: 100),
                     CGRect(x: 100, y: 0, width: 100, height: 100)]
        XCTAssertEqual(ScreenPicker.indexContaining(CGPoint(x: 150, y: 50), in: rects), 1)
        XCTAssertEqual(ScreenPicker.indexContaining(CGPoint(x: 50, y: 50), in: rects), 0)
    }

    func testReturnsNilWhenNoRectContainsPoint() {
        let rects = [CGRect(x: 0, y: 0, width: 100, height: 100)]
        XCTAssertNil(ScreenPicker.indexContaining(CGPoint(x: 250, y: 250), in: rects))
    }

    func testWindowOnHorizontalSecondMonitorMapsToThatScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        // Top-left CG bounds centered on the right monitor.
        let cg = CGRect(x: 1400, y: 100, width: 200, height: 150)
        XCTAssertEqual(ScreenPicker.indexForWindow(topLeftBounds: cg, primaryHeight: 800, in: [primary, right]), 1)
    }

    func testWindowAbovePrimaryFlipsYCorrectly() {
        // A monitor above the primary in AppKit space (origin.y = 800) is at
        // negative y in top-left CG coordinates.
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let top = CGRect(x: 0, y: 800, width: 1000, height: 600)
        let cg = CGRect(x: 400, y: -500, width: 200, height: 400) // midY -300 -> AppKit y 1100
        XCTAssertEqual(ScreenPicker.indexForWindow(topLeftBounds: cg, primaryHeight: 800, in: [primary, top]), 1)
    }
}
