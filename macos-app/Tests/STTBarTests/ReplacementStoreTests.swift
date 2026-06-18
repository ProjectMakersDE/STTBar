import XCTest
@testable import STTBar

final class ReplacementStoreTests: XCTestCase {
    private func dir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testLoadsLegacyAndExtendedTsv() throws {
        let d = dir()
        let file = d.appendingPathComponent("stt-replacements.tsv")
        try """
        horizon\thorizOn
        0\tfoo\tbar\tAllgemein\tignored
        1\tbody seasons\tBodySeasons\tProjekt\tbrand

        """.write(to: file, atomically: true, encoding: .utf8)
        let store = ReplacementStore(directory: d)
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries[0].from, "horizon")
        XCTAssertFalse(store.entries[1].enabled)
        XCTAssertEqual(store.preview("horizon und body seasons und foo"), "horizOn und BodySeasons und foo")
    }
}
