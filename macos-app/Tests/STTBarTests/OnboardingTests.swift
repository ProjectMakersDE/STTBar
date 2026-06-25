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
        XCTAssertTrue(OnboardingReadiness.isValidHTTPURL("http://192.168.30.30:8082/v1/audio/transcriptions"))
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
                                                       whisperURL: "http://192.168.30.30:8082/v1/audio/transcriptions",
                                                       currentSource: "server"),
            "server")
    }

    func testPreferredInitialSourcePrefersDownloadedLocalModel() {
        XCTAssertEqual(
            OnboardingReadiness.preferredInitialSource(localModelDownloaded: true,
                                                       whisperURL: "http://192.168.30.30:8082/x",
                                                       currentSource: "server"),
            "local")
    }

    func testLocalModelDownloadedScan() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sttbar-models-\(UInt32.random(in: 0..<99999))")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        XCTAssertFalse(OnboardingReadiness.localModelDownloaded(in: tmp), "empty dir has no model")
        let model = tmp.appendingPathComponent("argmaxinc/openai_whisper-base/AudioEncoder.mlmodelc")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        XCTAssertTrue(OnboardingReadiness.localModelDownloaded(in: tmp), "a .mlmodelc means a model is present")
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
        XCTAssertEqual(Hotkey.rawF5.keyCode, UInt32(kVK_F5))
        XCTAssertEqual(Hotkey.rawF5.display, "F5")
    }
}
