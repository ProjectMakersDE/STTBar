import AppKit
import XCTest
@testable import STTBar

final class HudAnchorTests: XCTestCase {
    func testAllAnchorsResolveToUniquePositions() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 190, height: 46)
        let points = HudAnchor.allCases.map { $0.origin(for: size, in: screen) }
        XCTAssertEqual(Set(points.map { "\(Int($0.x)):\(Int($0.y))" }).count, HudAnchor.allCases.count)
    }
}
