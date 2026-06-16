import XCTest
@testable import STTBar

final class AudioLevelReaderTests: XCTestCase {
    /// Builds a fake 44-byte-header + N int16 samples wav-ish file (only the
    /// PCM tail matters to the reader).
    private func wav(samples: [Int16]) -> URL {
        var data = Data(count: 44) // dummy header
        for s in samples { withUnsafeBytes(of: s.littleEndian) { data.append(contentsOf: $0) } }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try! data.write(to: u); return u
    }

    func testSilenceIsLow() {
        let r = AudioLevelReader(bucketCount: 22)
        let levels = r.levels(from: wav(samples: Array(repeating: 0, count: 4400)))
        XCTAssertEqual(levels.count, 22)
        XCTAssertTrue(levels.allSatisfy { $0 < 0.05 })
    }

    func testLoudIsHigher() {
        let r = AudioLevelReader(bucketCount: 22)
        let loud = r.levels(from: wav(samples: Array(repeating: 30000, count: 4400)))
        let quiet = r.levels(from: wav(samples: Array(repeating: 200, count: 4400)))
        XCTAssertGreaterThan(loud.reduce(0,+), quiet.reduce(0,+))
    }

    func testMissingFileReturnsZeros() {
        let r = AudioLevelReader(bucketCount: 22)
        let levels = r.levels(from: URL(fileURLWithPath: "/no/such.wav"))
        XCTAssertEqual(levels, Array(repeating: 0, count: 22))
    }
}
