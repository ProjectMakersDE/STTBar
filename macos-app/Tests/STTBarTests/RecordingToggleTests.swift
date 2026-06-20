import XCTest
@testable import STTBar

final class RecordingToggleTests: XCTestCase {
    private let toggle = RecordingToggle(debounce: 0.35)
    private let now = Date(timeIntervalSince1970: 1_000)

    func testIdlePressStartsCleanly() {
        let action = toggle.decide(isLiveRecording: false, isBusy: false, lastTriggerAt: nil, now: now)
        XCTAssertEqual(action, .start)
    }

    func testLiveRecordingPressStops() {
        let action = toggle.decide(isLiveRecording: true, isBusy: false, lastTriggerAt: nil, now: now)
        XCTAssertEqual(action, .stop)
    }

    // The user's rule: pressing while a previous run is still transcribing (no
    // live audio) must not be swallowed — it becomes a queued fresh start.
    func testBusyWithoutLiveRecordingQueuesStart() {
        let action = toggle.decide(isLiveRecording: false, isBusy: true, lastTriggerAt: nil, now: now)
        XCTAssertEqual(action, .queueStart)
    }

    // A live recording wins over the busy flag: it is still a stop.
    func testBusyWithLiveRecordingStops() {
        let action = toggle.decide(isLiveRecording: true, isBusy: true, lastTriggerAt: nil, now: now)
        XCTAssertEqual(action, .stop)
    }

    func testRapidRefirePressIsIgnored() {
        let last = now.addingTimeInterval(-0.1) // within debounce window
        let action = toggle.decide(isLiveRecording: false, isBusy: false, lastTriggerAt: last, now: now)
        XCTAssertEqual(action, .ignore)
    }

    func testPressAfterDebounceIsHonored() {
        let last = now.addingTimeInterval(-0.5) // outside debounce window
        let action = toggle.decide(isLiveRecording: false, isBusy: false, lastTriggerAt: last, now: now)
        XCTAssertEqual(action, .start)
    }

    func testDebounceAppliesEvenWhileRecording() {
        let last = now.addingTimeInterval(-0.1)
        let action = toggle.decide(isLiveRecording: true, isBusy: false, lastTriggerAt: last, now: now)
        XCTAssertEqual(action, .ignore)
    }
}
