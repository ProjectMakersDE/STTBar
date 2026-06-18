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

    func testUpdateStoresPreviousPromptVersion() throws {
        let d = dir()
        var store = try PromptStore(directory: d, defaultBody: "A")
        let id = store.activePrompt!.id
        try store.update(id, title: "Renamed", body: "B", note: "Changed")
        XCTAssertEqual(store.activePrompt?.versions.count, 1)
        XCTAssertEqual(store.activePrompt?.versions.first?.body, "A")
        XCTAssertEqual(store.activePrompt?.versions.first?.note, "Changed")
    }

    func testSeedsMultipleBuiltInPrompts() throws {
        let d = dir()
        let store = try PromptStore(directory: d, defaultPrompts: [
            PromptSeed(title: "DE", body: "A"),
            PromptSeed(title: "EN", body: "B"),
        ])

        XCTAssertEqual(store.prompts.map(\.title), ["DE", "EN"])
        XCTAssertEqual(store.activePrompt?.title, "DE")
    }

    func testMigratesLegacyBuiltInPromptAndKeepsVersion() throws {
        let d = dir()
        var old = try PromptStore(directory: d, defaultPrompts: [
            PromptSeed(title: "Agent-Standard (DE)", body: "old body with endpoint marker"),
        ])
        let id = old.activePrompt!.id
        try old.update(id, title: "Agent-Standard (DE)", body: "legacy body with endpoint marker")

        let migrated = try PromptStore(directory: d, defaultPrompts: [
            PromptSeed(title: "Agent V4 (DE)",
                       body: "new body",
                       legacyTitles: ["Agent-Standard (DE)"],
                       legacyBodyMarkers: ["endpoint marker"]),
            PromptSeed(title: "Agent V4 (EN output)", body: "english body"),
        ])

        XCTAssertEqual(migrated.prompts.first(where: { $0.id == id })?.title, "Agent V4 (DE)")
        XCTAssertEqual(migrated.prompts.first(where: { $0.id == id })?.body, "new body")
        XCTAssertEqual(migrated.prompts.first(where: { $0.id == id })?.versions.first?.body, "legacy body with endpoint marker")
        XCTAssertTrue(migrated.prompts.contains { $0.title == "Agent V4 (EN output)" })
    }
}
