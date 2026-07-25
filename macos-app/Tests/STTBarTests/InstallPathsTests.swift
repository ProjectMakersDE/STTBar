import XCTest
@testable import STTBar

final class InstallPathsTests: XCTestCase {
    private let container = URL(fileURLWithPath: "/container/Application Support/STTBar")
    private let outside = URL(fileURLWithPath: "/Users/someone/.local/share/stt")

    func testNoOverrideUsesContainer() {
        let resolved = InstallPaths.resolve(override: nil, container: container, isUsable: { _ in true })
        XCTAssertEqual(resolved, container)
    }

    func testEmptyOverrideUsesContainer() {
        let resolved = InstallPaths.resolve(override: "", container: container, isUsable: { _ in true })
        XCTAssertEqual(resolved, container)
    }

    func testReadableOverrideIsHonored() {
        let resolved = InstallPaths.resolve(override: outside.path, container: container, isUsable: { _ in true })
        XCTAssertEqual(resolved.path, outside.path)
    }

    /// The sandbox denies paths outside the container. Honoring one anyway gave
    /// an empty `.env` and a silent fall back to the default localhost whisper
    /// URL, which surfaced as "Could not connect to the server."
    func testUnreadableOverrideFallsBackToContainer() {
        let resolved = InstallPaths.resolve(override: outside.path, container: container, isUsable: { _ in false })
        XCTAssertEqual(resolved, container)
    }
}
