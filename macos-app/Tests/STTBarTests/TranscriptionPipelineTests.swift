import XCTest
import AVFoundation
@testable import STTBar

private func makeConfig(language: String = "de", provider: String = "lmstudio") -> TranscriptionConfig {
    TranscriptionConfig(whisperURL: "http://localhost:8000/v1/audio/transcriptions",
                        whisperModel: "Systran/faster-whisper-base", language: language,
                        postprocessEnabled: false, provider: provider, lmStudioURL: "http://localhost:1234/api/v1/chat",
                        llmModel: "m", promptBody: "SYS", transcribeTimeout: 30,
                        postprocessTimeout: 60, temperature: 0, reasoning: "off",
                        replacements: ReplacementStore(directory: FileManager.default.temporaryDirectory),
                        source: "server", localModel: "")
}

final class TranscriptionConfigTests: XCTestCase {
    func testLanguageOmittedWhenAuto() {
        XCTAssertNil(TranscriptionConfig.languageParam(for: "auto"))
        XCTAssertNil(TranscriptionConfig.languageParam(for: "  AUTO "))
        XCTAssertNil(TranscriptionConfig.languageParam(for: ""))
        XCTAssertEqual(TranscriptionConfig.languageParam(for: "de"), "de")
    }
}

final class WhisperClientTests: XCTestCase {
    func testBodyIncludesModelResponseFormatAndLanguage() {
        let body = WhisperClient().multipartBody(audioData: Data([0x52, 0x49, 0x46, 0x46]),
            filename: "recording.wav", config: makeConfig(language: "de"), boundary: "B")
        let s = String(data: body, encoding: .ascii) ?? ""
        XCTAssertTrue(s.contains("name=\"model\"\r\n\r\nSystran/faster-whisper-base"))
        XCTAssertTrue(s.contains("name=\"response_format\"\r\n\r\njson"))
        XCTAssertTrue(s.contains("name=\"language\"\r\n\r\nde"))
        XCTAssertTrue(s.contains("name=\"file\"; filename=\"recording.wav\""))
    }

    func testBodyOmitsLanguageWhenAuto() {
        let body = WhisperClient().multipartBody(audioData: Data([0x00]),
            filename: "r.wav", config: makeConfig(language: "auto"), boundary: "B")
        let s = String(data: body, encoding: .ascii) ?? ""
        XCTAssertFalse(s.contains("name=\"language\""))
    }

    func testParseTextReadsTextField() {
        let json = #"{"text":"hallo welt"}"#.data(using: .utf8)!
        XCTAssertEqual(WhisperClient.parseText(json), "hallo welt")
        XCTAssertNil(WhisperClient.parseText(#"{"text":""}"#.data(using: .utf8)!))
        XCTAssertNil(WhisperClient.parseText(Data("not json".utf8)))
    }
}

final class LLMClientTests: XCTestCase {
    func testOpenAIBodyHasSystemAndUserMessages() {
        let data = LLMClient.body(provider: "openai", model: "m", prompt: "SYS", transcript: "USR", temperature: 0, reasoning: "off")
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let messages = obj["messages"] as! [[String: String]]
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "SYS")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "USR")
        XCTAssertEqual(obj["stream"] as? Bool, false)
    }

    func testLMStudioBodyUsesInputField() {
        let data = LLMClient.body(provider: "lmstudio", model: "m", prompt: "SYS", transcript: "USR", temperature: 0, reasoning: "off")
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["input"] as? String, "SYS\n\nUSR")
        XCTAssertEqual(obj["store"] as? Bool, false)
        XCTAssertEqual(obj["reasoning"] as? String, "off")
    }

    func testParseOpenAIResponse() {
        let json = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        XCTAssertEqual(LLMClient.parse(provider: "openai", json), "ok")
    }

    func testParseLMStudioResponseConcatenatesMessageContent() {
        let json = #"{"output":[{"type":"reasoning","content":"x"},{"type":"message","content":"ok"}]}"#.data(using: .utf8)!
        XCTAssertEqual(LLMClient.parse(provider: "lmstudio", json), "ok")
    }
}

final class AudioRecorderTests: XCTestCase {
    func testTargetFormatIs16kMono16bit() {
        XCTAssertEqual(AudioRecorder.targetSettings[AVSampleRateKey] as? Int, 16000)
        XCTAssertEqual(AudioRecorder.targetSettings[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(AudioRecorder.targetSettings[AVLinearPCMBitDepthKey] as? Int, 16)
    }

    // After sleep/wake or display/dock changes the cached AVAudioEngine input
    // can report a dead format (0 Hz / 0 channels). Installing a tap with such
    // a format raises an Objective-C exception that Swift cannot catch, so the
    // recorder must reject it up front instead of crashing the app.
    func testDeadInputFormatsAreRejected() {
        XCTAssertFalse(AudioRecorder.isUsableInputFormat(sampleRate: 0, channelCount: 0))
        XCTAssertFalse(AudioRecorder.isUsableInputFormat(sampleRate: 0, channelCount: 1))
        XCTAssertFalse(AudioRecorder.isUsableInputFormat(sampleRate: 48_000, channelCount: 0))
    }

    func testLiveInputFormatsAreAccepted() {
        XCTAssertTrue(AudioRecorder.isUsableInputFormat(sampleRate: 48_000, channelCount: 1))
        XCTAssertTrue(AudioRecorder.isUsableInputFormat(sampleRate: 16_000, channelCount: 2))
        XCTAssertTrue(AudioRecorder.isUsableInputFormat(sampleRate: 44_100, channelCount: 1))
    }

    func testNoAudioInputErrorExplainsItself() {
        let message = AudioRecorderError.noAudioInput.localizedDescription
        XCTAssertFalse(message.isEmpty)
    }
}

final class TranscriptionSourceTests: XCTestCase {
    func testSourceMapping() {
        XCTAssertEqual(TranscriptionSource(rawValue: "local"), .local)
        XCTAssertEqual(TranscriptionSource(rawValue: "selfhost"), .selfHost)
        XCTAssertEqual(TranscriptionSource(rawValue: "server"), .server)
        XCTAssertNil(TranscriptionSource(rawValue: "bogus"))
    }

    func testIsLocalOnlyForLocal() {
        XCTAssertTrue(Transcribers.isLocal(.local))
        XCTAssertFalse(Transcribers.isLocal(.server))
        XCTAssertFalse(Transcribers.isLocal(.selfHost))
    }
}

final class WhisperModelManagerTests: XCTestCase {
    func testRecommendationScalesWithRAM() {
        let m = WhisperModelManager()
        XCTAssertEqual(m.recommendedModel(physicalMemoryBytes: 8 * 1_073_741_824), "base")
        XCTAssertEqual(m.recommendedModel(physicalMemoryBytes: 16 * 1_073_741_824), "small")
        XCTAssertEqual(m.recommendedModel(physicalMemoryBytes: 32 * 1_073_741_824), "large-v3-v20240930_626MB")
    }
}

final class NativeBackendModeTests: XCTestCase {
    func testModeMapping() {
        XCTAssertTrue(NativeBackend.usesLLM(.full))
        XCTAssertTrue(NativeBackend.usesLLM(.english))
        XCTAssertFalse(NativeBackend.usesLLM(.raw))
        XCTAssertEqual(NativeBackend.translateTarget(.english), "English")
        XCTAssertNil(NativeBackend.translateTarget(.full))
        XCTAssertNil(NativeBackend.translateTarget(.raw))
    }
}
