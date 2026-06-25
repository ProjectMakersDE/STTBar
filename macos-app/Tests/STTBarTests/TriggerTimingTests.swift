import XCTest
@testable import STTBar

final class TriggerTimingTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000)

    func testFirstEventHasNoInterval() {
        let timing = TriggerTiming(previousRawEventAt: nil, eventAt: base, handledAt: base)
        XCTAssertNil(timing.intervalMs)
        XCTAssertEqual(timing.intervalToken, "first")
    }

    func testIntervalBetweenConsecutiveRawEventsInMilliseconds() {
        let previous = base
        let event = base.addingTimeInterval(0.042) // 42 ms later
        let timing = TriggerTiming(previousRawEventAt: previous, eventAt: event, handledAt: event)
        XCTAssertEqual(timing.intervalMs, 42)
        XCTAssertEqual(timing.intervalToken, "42")
    }

    func testHandlingLatencyMeasuresMainThreadDelay() {
        let event = base
        let handled = base.addingTimeInterval(0.0125) // handled 12.5 ms later
        let timing = TriggerTiming(previousRawEventAt: nil, eventAt: event, handledAt: handled)
        XCTAssertEqual(timing.latencyMs, 13) // rounded
    }

    func testLatencyNeverNegative() {
        let event = base
        let handled = base.addingTimeInterval(-0.5) // clock skew: handled "before" event
        let timing = TriggerTiming(previousRawEventAt: nil, eventAt: event, handledAt: handled)
        XCTAssertEqual(timing.latencyMs, 0)
    }
}
