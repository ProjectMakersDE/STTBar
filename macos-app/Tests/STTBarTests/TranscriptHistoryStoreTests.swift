import XCTest
@testable import STTBar

final class TranscriptHistoryStoreTests: XCTestCase {
    private var directory: URL!
    private var suite: String!
    private var settings: AppSettings!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var url: URL { directory.appendingPathComponent("transcript-history.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "STTBar.HistoryTests.\(UUID().uuidString)"
        settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        settings.historyEnabled = true
        settings.historyRetentionHours = 1
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func store() -> TranscriptHistoryStore {
        TranscriptHistoryStore(directory: directory, settings: settings, now: { self.now })
    }

    func testStartupRemovesExpiredHistoryFromDisk() throws {
        let fixture = [TranscriptHistoryItem(date: now.addingTimeInterval(-48 * 3600), mode: "raw", text: "expired fixture")]
        try JSONEncoder().encode(fixture).write(to: url)
        XCTAssertTrue(store().items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testPeriodicPurgeExpiresHistoryEvenWhenSavingIsDisabledOrSensitive() throws {
        let store = store()
        store.add(text: "fixture", mode: .raw)
        settings.historyEnabled = false
        settings.sensitiveMode = true
        now = now.addingTimeInterval(3601)
        XCTAssertTrue(store.purgeExpired())
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(store.purgeExpired())
    }

    func testDisabledAddStillPurgesButDoesNotSaveNewTranscript() {
        let store = store()
        store.add(text: "old fixture", mode: .raw)
        now = now.addingTimeInterval(3601)
        settings.sensitiveMode = true
        store.add(text: "sensitive fixture", mode: .raw)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testRetentionChangePurgesWithoutAnotherDictation() {
        settings.historyRetentionHours = 24
        let store = store()
        store.add(text: "fixture", mode: .raw)
        now = now.addingTimeInterval(2 * 3600)
        settings.historyRetentionHours = 1
        XCTAssertTrue(store.purgeExpired())
        XCTAssertTrue(store.items.isEmpty)
    }

    func testHistoryUsesInjectedTimeAndKeepsNewestTwenty() throws {
        let store = store()
        for index in 0..<25 { store.add(text: "fixture \(index)", mode: .raw) }
        XCTAssertEqual(store.items.count, 20)
        XCTAssertEqual(store.items.first?.text, "fixture 24")
        XCTAssertEqual(store.items.first?.date, now)
        let disk = try JSONDecoder().decode([TranscriptHistoryItem].self, from: Data(contentsOf: url))
        XCTAssertEqual(disk, store.items)
    }
}
