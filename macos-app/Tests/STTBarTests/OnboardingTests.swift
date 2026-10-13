import Carbon.HIToolbox
import XCTest
@testable import STTBar

final class OnboardingReadinessTests: XCTestCase {
    private func inputs(source: String, model: Bool = false, url: Bool = false, mic: Bool = false) -> OnboardingReadiness.Inputs {
        OnboardingReadiness.Inputs(source: source, localModelDownloaded: model, whisperURLValid: url, micAuthorized: mic)
    }

    func testLocalNeedsMicAndModel() {
        let r = OnboardingReadiness.blockingReasons(inputs(source: "local"))
        XCTAssertEqual(Set(r), ["microphone", "localModel"])
    }

    func testLocalUsableWhenMicAndModelPresent() {
        let i = inputs(source: "local", model: true, mic: true)
        XCTAssertTrue(OnboardingReadiness.isUsable(i))
        XCTAssertEqual(OnboardingReadiness.blockingReasons(i), [])
    }

    func testLocalIgnoresServerURL() {
        // A missing/invalid server URL must not block the local path.
        let i = inputs(source: "local", model: true, url: false, mic: true)
        XCTAssertTrue(OnboardingReadiness.isUsable(i))
    }

    func testServerNeedsValidURL() {
        let r = OnboardingReadiness.blockingReasons(inputs(source: "server", mic: true))
        XCTAssertEqual(r, ["serverURL"])
    }

    func testServerUsableWithURLAndMic() {
        XCTAssertTrue(OnboardingReadiness.isUsable(inputs(source: "server", url: true, mic: true)))
    }

    func testSelfHostBehavesLikeServer() {
        XCTAssertEqual(OnboardingReadiness.blockingReasons(inputs(source: "selfhost", mic: true)), ["serverURL"])
    }

    func testValidHTTPURL() {
        XCTAssertTrue(OnboardingReadiness.isValidHTTPURL("http://192.168.1.50:8082/v1/audio/transcriptions"))
        XCTAssertTrue(OnboardingReadiness.isValidHTTPURL("https://example.com/x"))
        XCTAssertFalse(OnboardingReadiness.isValidHTTPURL(""))
        XCTAssertFalse(OnboardingReadiness.isValidHTTPURL("ftp://example.com"))
        XCTAssertFalse(OnboardingReadiness.isValidHTTPURL("not a url"))
    }

    func testPreferredInitialSourceSteersFreshUserToLocal() {
        // Fresh user: no model, only the localhost default URL → local.
        XCTAssertEqual(
            OnboardingReadiness.preferredInitialSource(localModelDownloaded: false,
                                                       whisperURL: "http://localhost:8082/v1/audio/transcriptions",
                                                       currentSource: "server"),
            "local")
    }

    func testPreferredInitialSourceKeepsRealRemote() {
        // A deliberately configured LAN/remote server is kept, not overridden.
        XCTAssertEqual(
            OnboardingReadiness.preferredInitialSource(localModelDownloaded: false,
                                                       whisperURL: "http://192.168.1.50:8082/v1/audio/transcriptions",
                                                       currentSource: "server"),
            "server")
    }

    func testPreferredInitialSourcePrefersDownloadedLocalModel() {
        XCTAssertEqual(
            OnboardingReadiness.preferredInitialSource(localModelDownloaded: true,
                                                       whisperURL: "http://192.168.1.50:8082/x",
                                                       currentSource: "server"),
            "local")
    }

    func testLocalModelDownloadedRequiresCompleteSelectedModel() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sttbar-models-\(UInt32.random(in: 0..<99999))")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        XCTAssertFalse(OnboardingReadiness.localModelDownloaded("base", in: tmp))
        let folder = tmp.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-base")
        for component in ["AudioEncoder", "MelSpectrogram", "TextDecoder"] {
            let bundle = folder.appendingPathComponent("\(component).mlmodelc")
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            XCTAssertFalse(OnboardingReadiness.localModelDownloaded("base", in: tmp), "empty bundles are incomplete")
            try Data([1]).write(to: bundle.appendingPathComponent("coremldata.bin"))
        }
        XCTAssertFalse(OnboardingReadiness.localModelDownloaded("base", in: tmp), "tokenizer is also required offline")
        let tokenizer = tmp.appendingPathComponent("models/openai/whisper-base")
        try FileManager.default.createDirectory(at: tokenizer, withIntermediateDirectories: true)
        try Data("{\"model\":{\"type\":\"BPE\",\"vocab\":{\"a\":0},\"merges\":[]}}".utf8).write(to: tokenizer.appendingPathComponent("tokenizer.json"))
        XCTAssertFalse(OnboardingReadiness.localModelDownloaded("base", in: tmp), "tokenizer configuration is also required offline")
        try Data("{\"tokenizer_class\":\"WhisperTokenizer\"}".utf8).write(to: tokenizer.appendingPathComponent("tokenizer_config.json"))
        XCTAssertTrue(OnboardingReadiness.localModelDownloaded("base", in: tmp))
        XCTAssertFalse(OnboardingReadiness.localModelDownloaded("small", in: tmp), "another model cannot satisfy selection")
        try Data("truncated".utf8).write(to: tokenizer.appendingPathComponent("tokenizer.json"))
        XCTAssertFalse(OnboardingReadiness.localModelDownloaded("base", in: tmp), "invalid tokenizer cannot satisfy selection")
        try Data("{\"model\":{\"type\":\"BPE\",\"vocab\":{\"a\":0}}}".utf8).write(to: tokenizer.appendingPathComponent("tokenizer.json"))
        XCTAssertFalse(OnboardingReadiness.localModelDownloaded("base", in: tmp), "BPE data missing merges cannot satisfy selection")
    }

    func testCompletionFlagRoundTrip() {
        let suite = "OnboardingTests-\(UInt32.random(in: 0..<99999))"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertNil(d.object(forKey: OnboardingReadiness.completedKey))
        OnboardingReadiness.markCompleted(d)
        XCTAssertNotNil(d.object(forKey: OnboardingReadiness.completedKey))
        OnboardingReadiness.resetCompleted(d)
        XCTAssertNil(d.object(forKey: OnboardingReadiness.completedKey))
    }
}

final class OnboardingModelTests: XCTestCase {
    private let ready = OnboardingReadiness.Inputs(source: "local", localModelDownloaded: true, whisperURLValid: false, micAuthorized: true)

    func testRequiredPermissionAndConfigurationGateForward() {
        let m = OnboardingModel()
        m.stepIndex = m.steps.firstIndex(of: .permissions)!
        var missing = ready
        missing.micAuthorized = false
        XCTAssertFalse(m.advance(inputs: missing, apply: { true }))
        XCTAssertEqual(m.step, .permissions)
        XCTAssertTrue(m.advance(inputs: ready, apply: { true }))
        missing = ready
        missing.localModelDownloaded = false
        XCTAssertFalse(m.advance(inputs: missing, apply: { true }))
        XCTAssertFalse(m.advance(inputs: ready, apply: { false }), "save failure must keep the configure step open")
        XCTAssertEqual(m.step, .configure)
        XCTAssertTrue(m.advance(inputs: ready, apply: { true }))
    }

    func testOptionalTestAndAccessibilityDoNotBlockButFinishRechecksReadiness() {
        let m = OnboardingModel()
        m.stepIndex = m.steps.firstIndex(of: .test)!
        XCTAssertNil(m.lastTestTranscript)
        XCTAssertTrue(m.advance(inputs: ready, apply: { true }))
        let suite = "OnboardingFinishTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(m.complete(inputs: ready, apply: { false }, defaults: defaults))
        XCTAssertNil(defaults.object(forKey: OnboardingReadiness.completedKey))
        var revoked = ready
        revoked.micAuthorized = false
        XCTAssertFalse(m.complete(inputs: revoked, apply: { true }, defaults: defaults))
        XCTAssertNil(defaults.object(forKey: OnboardingReadiness.completedKey))
        XCTAssertTrue(m.complete(inputs: ready, apply: { true }, defaults: defaults))
        XCTAssertNotNil(defaults.object(forKey: OnboardingReadiness.completedKey))
    }

    func testStepProgression() {
        let m = OnboardingModel()
        XCTAssertEqual(m.step, .welcome)
        XCTAssertFalse(m.canBack)
        XCTAssertEqual(m.progress, 0, accuracy: 0.001)
        m.next()
        XCTAssertEqual(m.step, .source)
        XCTAssertTrue(m.canBack)
        m.back()
        XCTAssertEqual(m.step, .welcome)
    }

    func testCannotGoBeyondBounds() {
        let m = OnboardingModel()
        m.back()
        XCTAssertEqual(m.stepIndex, 0)
        for _ in 0..<50 { m.next() }
        XCTAssertEqual(m.step, .done)
        XCTAssertTrue(m.isLast)
        XCTAssertEqual(m.progress, 1, accuracy: 0.001)
    }
}

final class HotkeyFunctionKeyTests: XCTestCase {
    func testF5HasAReadableName() {
        XCTAssertEqual(Hotkey.keyName(UInt32(kVK_F5)), "F5")
        XCTAssertEqual(Hotkey.keyName(UInt32(kVK_F1)), "F1")
    }
}
