import XCTest
@testable import STTBar

final class WaveLevelFilterTests: XCTestCase {
    private let delta = 0.016 // ~one 60fps frame

    func testRisesTowardHigherTarget() {
        let next = WaveLevelFilter.step(current: 0, target: 1, delta: delta, decaySpeed: 1)
        XCTAssertGreaterThan(next, 0)
        XCTAssertLessThan(next, 1) // a single frame does not jump all the way
    }

    func testDecaysTowardLowerTarget() {
        let next = WaveLevelFilter.step(current: 1, target: 0, delta: delta, decaySpeed: 1)
        XCTAssertLessThan(next, 1)
        XCTAssertGreaterThan(next, 0)
    }

    func testHigherDecaySpeedDecaysFasterPerFrame() {
        let slow = WaveLevelFilter.step(current: 1, target: 0, delta: delta, decaySpeed: 1)
        let fast = WaveLevelFilter.step(current: 1, target: 0, delta: delta, decaySpeed: 3)
        XCTAssertLessThan(fast, slow) // larger decaySpeed => lower (faster release)
    }

    func testResultStaysInUnitRange() {
        XCTAssertEqual(WaveLevelFilter.step(current: 0.9, target: 5, delta: 1, decaySpeed: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(WaveLevelFilter.step(current: 0.1, target: -2, delta: 1, decaySpeed: 1), 0, accuracy: 0.0001)
    }
}

final class HudWaveStyleTests: XCTestCase {
    func testFiveSwitchableStylesIncludingBars() {
        XCTAssertEqual(HudWaveStyle.allCases.count, 5)
        XCTAssertTrue(HudWaveStyle.allCases.contains(.bars))
    }

    func testRawValueRoundTripsForPersistence() {
        XCTAssertEqual(HudWaveStyle(rawValue: "line"), .line)
        XCTAssertNil(HudWaveStyle(rawValue: "not-a-style"))
    }

    func testEveryStyleHasANonEmptyLabel() {
        for style in HudWaveStyle.allCases {
            XCTAssertFalse(style.label.isEmpty)
        }
    }
}
