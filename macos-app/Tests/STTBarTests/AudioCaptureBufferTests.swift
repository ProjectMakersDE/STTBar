import AVFoundation
import XCTest
@testable import STTBar

/// The capture buffer is sized before the unit starts, from a value the audio
/// unit only *reports*. A callback that delivers more frames than that has no
/// room to land in, and used to be discarded without a trace.
final class AudioCaptureBufferTests: XCTestCase {
    private func makeSink(capacity: Int) throws -> CaptureSink {
        let deviceFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                       sampleRate: 48000,
                                                       channels: 1,
                                                       interleaved: true))
        let targetFormat = try XCTUnwrap(AVAudioFormat(settings: AudioRecorder.targetSettings))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("capture-sink-\(UUID().uuidString).wav")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forWriting: url, settings: AudioRecorder.targetSettings,
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        return try XCTUnwrap(CaptureSink(deviceFormat: deviceFormat, targetFormat: targetFormat,
                                         file: file, maxFrames: capacity))
    }

    // MARK: Buffer capacity

    func testCapacityNeverDropsBelowTheSafetyFloor() {
        XCTAssertEqual(AudioRecorder.captureCapacity(reported: 512), 4096)
    }

    func testCapacityFollowsTheUnitWhenItAsksForMore() {
        XCTAssertEqual(AudioRecorder.captureCapacity(reported: 8192), 8192)
    }

    func testCapacitySurvivesAUnitThatReportsNothing() {
        XCTAssertEqual(AudioRecorder.captureCapacity(reported: 0), 4096)
    }

    // MARK: Oversized callbacks are counted, not swallowed

    func testSinkAcceptsAFullBuffer() throws {
        let sink = try makeSink(capacity: 512)
        XCTAssertTrue(sink.accepts(frames: 512))
    }

    func testSinkRejectsMoreFramesThanItCanHold() throws {
        let sink = try makeSink(capacity: 512)
        XCTAssertFalse(sink.accepts(frames: 513))
    }

    func testRejectedCallbacksAreCounted() throws {
        let sink = try makeSink(capacity: 512)
        sink.noteDropped()
        sink.noteDropped()
        XCTAssertEqual(sink.dropped, 2)
    }

    func testAFreshSinkReportsNoDrops() throws {
        let sink = try makeSink(capacity: 512)
        XCTAssertEqual(sink.dropped, 0)
        XCTAssertEqual(sink.callbacks, 0)
    }
}
