import XCTest
@testable import STTBar

final class SettingsModelTests: XCTestCase {
    private var directory: URL!
    private var suite: String!
    private var settings: AppSettings!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "STTBar.SettingsTests.\(UUID().uuidString)"
        settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func model() -> SettingsModel {
        SettingsModel(installDir: directory, appSettings: settings,
                      apiKeyReader: { _ in "" }, apiKeyWriter: { _, _ in })
    }

    func testPrivacyApplyDoesNotApplyOrValidateServerDraft() throws {
        let model = model()
        model.whisperURL = "unfinished server address"
        model.postprocessEnabled = true
        model.lmStudioURL = ""
        model.sensitiveMode = true
        var changes = 0
        model.onPrivacySettingsChanged = { changes += 1 }
        XCTAssertTrue(model.applyPrivacyChanges())
        XCTAssertTrue(settings.sensitiveMode)
        XCTAssertTrue(model.effectiveSensitiveMode)
        XCTAssertFalse(model.effectiveHistoryEnabled)
        XCTAssertFalse(model.privacyChangesPending)
        XCTAssertNil(model.validationMessage)
        XCTAssertEqual(changes, 1)
        let env = try EnvStore(url: directory.appendingPathComponent(".env"))
        XCTAssertEqual(env.value("STT_SENSITIVE_MODE"), "1")
        XCTAssertNil(env.value("STT_SERVER_URL"))
    }

    func testInvalidPrivacyDraftShowsFailureAndEffectiveState() {
        settings.historyEnabled = true
        let model = model()
        model.sensitiveMode = true
        model.historyRetentionHours = "24h"
        XCTAssertFalse(model.applyPrivacyChanges())
        XCTAssertNotNil(model.validationMessage)
        XCTAssertNil(model.saveMessage)
        XCTAssertFalse(model.effectiveSensitiveMode)
        XCTAssertTrue(model.effectiveHistoryEnabled)
        XCTAssertTrue(model.privacyChangesPending)
    }

    func testLocalModeIgnoresUnusedServerAndDisabledLLMFields() {
        let model = model()
        model.transcriptionSource = "local"
        model.whisperURL = ""
        model.whisperModel = ""
        model.transcribeTimeout = ""
        model.provider = "unused"
        model.postprocessTimeout = "unused"
        XCTAssertTrue(model.applyEnvChanges())
        XCTAssertNil(model.validationMessage)
    }

    func testActiveBackendsRequireValidEndpointsAndPositiveTimeouts() {
        let model = model()
        model.whisperURL = "https://"
        XCTAssertFalse(model.validateDraft())
        model.transcriptionSource = "local"
        model.postprocessEnabled = true
        model.lmStudioURL = "https://llm.example.test/v1/chat/completions"
        model.postprocessTimeout = "0"
        XCTAssertFalse(model.validateDraft())
    }

    func testExportAndImportRestoreLocalSelectionAndKeepKeysOut() throws {
        let original = model()
        original.transcriptionSource = "local"
        original.localModel = "small"
        original.localPreload = false
        original.whisperAPIKey = "fixture-secret-whisper"
        original.llmAPIKey = "fixture-secret-llm"
        let data = try original.makeExportData()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("fixture-secret"))
        let bundle = try SettingsBundleCodec.decode(data)
        XCTAssertEqual(bundle.env["STT_SOURCE"], "local")
        XCTAssertEqual(bundle.env["STT_LOCAL_MODEL"], "small")
        let restored = model()
        XCTAssertTrue(restored.importBundle(data: data))
        XCTAssertEqual(restored.transcriptionSource, "local")
        XCTAssertEqual(restored.localModel, "small")
        XCTAssertFalse(restored.localPreload)
    }

    func testDeferredApiKeysLoadOffLaunchAndAreNotClearedBeforehand() throws {
        var reads = 0, writes = 0
        let model = SettingsModel(installDir: directory, appSettings: settings,
                                  apiKeyReader: { _ in reads += 1; return "fixture-key" },
                                  apiKeyWriter: { _, _ in writes += 1 },
                                  deferApiKeys: true)
        model.whisperURL = "https://example.invalid/v1/audio/transcriptions"
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(model.whisperAPIKey, "")
        XCTAssertTrue(model.applyEnvChanges())
        XCTAssertEqual(writes, 0)
        let loaded = expectation(description: "keys loaded")
        model.loadApiKeysInBackground { loaded.fulfill() }
        wait(for: [loaded], timeout: 5)
        XCTAssertEqual(model.whisperAPIKey, "fixture-key")
        XCTAssertGreaterThan(reads, 0)
    }

    func testLocalPreloadDefaultsOn() {
        XCTAssertTrue(model().localPreload)
    }

    func testLegacyBundleWithoutVersionPreservesMissingLocalSelection() throws {
        let model = model()
        model.transcriptionSource = "local"
        model.localModel = "base"
        XCTAssertTrue(model.applyEnvChanges())
        let old = Data(#"{"env":{"STT_LANGUAGE":"en"},"prompts":[],"replacements":[],"profiles":[]}"#.utf8)
        XCTAssertTrue(model.importBundle(data: old))
        XCTAssertEqual(model.transcriptionSource, "local")
        XCTAssertEqual(model.localModel, "base")
        XCTAssertEqual(model.language, "en")
    }

    func testUnknownImportKeyIsRejectedBeforeChangingFiles() throws {
        let model = model()
        let before = try Data(contentsOf: directory.appendingPathComponent(".env"))
        let data = Data(#"{"env":{"STT_LANGUAGE":"en","PATH":"attacker"},"prompts":[],"replacements":[],"profiles":[]}"#.utf8)
        XCTAssertFalse(model.importBundle(data: data))
        XCTAssertNotNil(model.validationMessage)
        XCTAssertNil(model.saveMessage)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(".env")), before)
        XCTAssertEqual(model.language, "de")
    }

    func testMalformedAndFutureBundlesReportFailure() {
        let model = model()
        XCTAssertFalse(model.importBundle(data: Data("broken JSON".utf8)))
        XCTAssertNotNil(model.validationMessage)
        let future = Data(#"{"version":999,"env":{},"prompts":[],"replacements":[],"profiles":[]}"#.utf8)
        XCTAssertFalse(model.importBundle(data: future))
        XCTAssertNotNil(model.validationMessage)
    }

    func testExportWriteFailureCannotReportSuccess() {
        let model = model()
        XCTAssertFalse(model.exportBundle(to: directory))
        XCTAssertNotNil(model.validationMessage)
        XCTAssertNil(model.saveMessage)
    }
}
