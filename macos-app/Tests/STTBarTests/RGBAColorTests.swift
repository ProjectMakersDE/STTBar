import XCTest
import AppKit
@testable import STTBar

final class RGBAColorTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let c = RGBAColor(r: 0.1, g: 0.2, b: 0.3, a: 0.45)
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(RGBAColor.self, from: data)
        XCTAssertEqual(back, c)
    }

    func testNSColorPreservesAlpha() {
        let c = RGBAColor(r: 0.5, g: 0.5, b: 0.5, a: 0.55)
        let ns = c.nsColor.usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(ns.alphaComponent), 0.55, accuracy: 0.001)
        XCTAssertEqual(Double(ns.redComponent), 0.5, accuracy: 0.001)
    }

    func testInitFromColorRoundTrips() {
        let original = RGBAColor(r: 0.2, g: 0.4, b: 0.6, a: 0.8)
        let viaColor = RGBAColor(original.color)
        XCTAssertEqual(viaColor.r, original.r, accuracy: 0.01)
        XCTAssertEqual(viaColor.g, original.g, accuracy: 0.01)
        XCTAssertEqual(viaColor.b, original.b, accuracy: 0.01)
        XCTAssertEqual(viaColor.a, original.a, accuracy: 0.01)
    }
}
