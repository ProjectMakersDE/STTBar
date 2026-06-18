import XCTest
@testable import STTBar

final class HudPhaseTimelineTests: XCTestCase {
    func testRecordingRunsAsSinglePhase() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timeline = HudPhaseTimeline()
        timeline.transition(to: .recording, from: .idle, at: start)

        let durations = timeline.durations(at: start.addingTimeInterval(7.2), state: .recording)

        XCTAssertEqual(durations.recording!, 7.2, accuracy: 0.001)
        XCTAssertNil(durations.whisper)
        XCTAssertNil(durations.llm)
        XCTAssertEqual(durations.total, 7.2, accuracy: 0.001)
    }

    func testWhisperFreezesRecordingAndAddsTotal() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timeline = HudPhaseTimeline()
        timeline.transition(to: .recording, from: .idle, at: start)
        timeline.transition(to: .whisper, from: .recording, at: start.addingTimeInterval(5))

        let durations = timeline.durations(at: start.addingTimeInterval(8), state: .whisper)

        XCTAssertEqual(durations.recording!, 5, accuracy: 0.001)
        XCTAssertEqual(durations.whisper!, 3, accuracy: 0.001)
        XCTAssertNil(durations.llm)
        XCTAssertEqual(durations.total, 8, accuracy: 0.001)
    }

    func testLlmFreezesWhisperAndRunsTotal() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timeline = HudPhaseTimeline()
        timeline.transition(to: .recording, from: .idle, at: start)
        timeline.transition(to: .whisper, from: .recording, at: start.addingTimeInterval(4))
        timeline.transition(to: .llm, from: .whisper, at: start.addingTimeInterval(7))

        let durations = timeline.durations(at: start.addingTimeInterval(9), state: .llm)

        XCTAssertEqual(durations.recording!, 4, accuracy: 0.001)
        XCTAssertEqual(durations.whisper!, 3, accuracy: 0.001)
        XCTAssertEqual(durations.llm!, 2, accuracy: 0.001)
        XCTAssertEqual(durations.total, 9, accuracy: 0.001)
    }
}
