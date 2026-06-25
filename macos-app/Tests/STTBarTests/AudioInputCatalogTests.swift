import XCTest
@testable import STTBar

final class AudioInputCatalogTests: XCTestCase {
    func testAutomaticIsAlwaysFirstAndPresentWhenNothingAvailable() {
        let ids = AudioInputCatalog.deviceIds(available: [], current: "")
        XCTAssertEqual(ids, [AudioInputCatalog.automatic])
        XCTAssertEqual(AudioInputCatalog.automatic, "")
    }

    func testAvailableDevicesFollowAutomaticInOrder() {
        let ids = AudioInputCatalog.deviceIds(available: ["MacBook Mic", "USB Mic"], current: "")
        XCTAssertEqual(ids, ["", "MacBook Mic", "USB Mic"])
    }

    func testCurrentDeviceInAvailableIsNotDuplicated() {
        let ids = AudioInputCatalog.deviceIds(available: ["MacBook Mic", "USB Mic"], current: "USB Mic")
        XCTAssertEqual(ids, ["", "MacBook Mic", "USB Mic"])
    }

    func testUnpluggedCurrentDeviceIsStillIncludedSoSelectionIsNotLost() {
        let ids = AudioInputCatalog.deviceIds(available: ["MacBook Mic"], current: "Unplugged Mic")
        XCTAssertEqual(ids, ["", "MacBook Mic", "Unplugged Mic"])
    }

    func testDuplicateAndEmptyAvailableNamesAreDropped() {
        let ids = AudioInputCatalog.deviceIds(available: ["Mic", "", "Mic"], current: "")
        XCTAssertEqual(ids, ["", "Mic"])
    }
}
