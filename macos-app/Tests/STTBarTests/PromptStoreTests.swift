import XCTest
@testable import STTBar

final class PromptStoreTests: XCTestCase {
    private func dir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testSeedsDefaultAndMirrorsActiveFile() throws {
        let d = dir()
        let store = try PromptStore(directory: d, defaultBody: "DEFAULT_BODY")
        XCTAssertEqual(store.prompts.count, 1)
        XCTAssertEqual(store.activePrompt?.body, "DEFAULT_BODY")
        let mirrored = try String(contentsOf: d.appendingPathComponent("active-prompt.txt"), encoding: .utf8)
        XCTAssertEqual(mirrored, "DEFAULT_BODY")
    }

    func testAddSwitchAndPersist() throws {
        let d = dir()
        var store = try PromptStore(directory: d, defaultBody: "A")
        let id = try store.add(title: "Second", body: "B")
        try store.setActive(id)
        XCTAssertEqual(store.activePrompt?.body, "B")
        let mirrored = try String(contentsOf: d.appendingPathComponent("active-prompt.txt"), encoding: .utf8)
        XCTAssertEqual(mirrored, "B")
        // Reload from disk preserves state
        let reloaded = try PromptStore(directory: d, defaultBody: "A")
        XCTAssertEqual(reloaded.activePrompt?.body, "B")
        XCTAssertEqual(reloaded.prompts.count, 2)
    }

    func testUpdateActiveBodyRewritesMirror() throws {
        let d = dir()
        var store = try PromptStore(directory: d, defaultBody: "A")
        let id = store.activePrompt!.id
        try store.update(id, title: "Renamed", body: "A2")
        let mirrored = try String(contentsOf: d.appendingPathComponent("active-prompt.txt"), encoding: .utf8)
        XCTAssertEqual(mirrored, "A2")
    }
}
