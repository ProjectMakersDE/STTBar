import XCTest
@testable import STTBar

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        Localization.shared.language = .de // restore default for other tests
        super.tearDown()
    }

    func testLReturnsPerLanguageString() {
        Localization.shared.language = .de
        XCTAssertEqual(L("Hallo", "Hello"), "Hallo")
        Localization.shared.language = .en
        XCTAssertEqual(L("Hallo", "Hello"), "Hello")
    }

    func testAppLanguageRoundTrips() {
        AppSettings.shared.appLanguage = .en
        XCTAssertEqual(AppSettings.shared.appLanguage, .en)
        AppSettings.shared.appLanguage = .de
        XCTAssertEqual(AppSettings.shared.appLanguage, .de)
    }

    func testSetAppLanguageSwitchesWhisperAndPrompt() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sttbar-lang-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = SettingsModel(installDir: dir)
        model.setAppLanguage(.en)
        XCTAssertEqual(Localization.shared.language, .en)
        XCTAssertEqual(model.language, "en")
        XCTAssertEqual(model.prompts.activePrompt?.title, DefaultPrompt.englishTitle)

        model.setAppLanguage(.de)
        XCTAssertEqual(model.language, "de")
        XCTAssertEqual(model.prompts.activePrompt?.title, DefaultPrompt.germanTitle)
    }
}
