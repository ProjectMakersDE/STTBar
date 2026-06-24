# App Store Phase 2 — Native Pipeline (Server Mode) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make STTBar transcribe end-to-end natively in the sandbox — record with `AVAudioEngine`, upload to the Whisper endpoint with `URLSession`, optionally clean with an LLM via `URLSession` — replacing the `PlaceholderBackend` from Phase 1 with a real `NativeBackend`. No shell.

**Architecture:** A new `NativeBackend` (conforms to the Phase-1 `TranscriptionBackend` protocol) orchestrates three focused, independently-testable components: `AudioRecorder` (16 kHz mono 16-bit WAV via `AVAudioEngine`, written to `RuntimePaths.recordingFile` so the existing HUD `AudioLevelReader` keeps working unchanged), `WhisperClient` (multipart `URLSession` upload → `.text`), and `LLMClient` (JSON `URLSession`, two providers). A plain `TranscriptionConfig` value struct snapshots `SettingsModel` at call time so the clients are pure and testable. Word replacements reuse the existing `ReplacementStore.preview(_:)`.

**Tech Stack:** Swift 5.9+, SwiftPM, AVFoundation (`AVAudioEngine`, `AVAudioConverter`, `AVAudioFile`), `URLSession`, XCTest.

## Global Constraints

- Recording format MUST be 16 kHz, mono, 16-bit signed little-endian PCM in a WAV container (matches what the Whisper endpoint expects; replicates `sox -r 16000 -c 1 -b 16`).
- Recording is written to `RuntimePaths.recordingFile` (the HUD's `AudioLevelReader` reads that file's tail — do not break it).
- Whisper request (replicates `stt-transcribe.sh`): `POST` to `settings.whisperURL` (full URL, e.g. `http://localhost:8000/v1/audio/transcriptions`), `multipart/form-data`, fields: `file` (the WAV), `model` = `settings.whisperModel`, `response_format` = `json`, and `language` = `settings.language` ONLY when it is not `"auto"`. No Authorization header (parity with the shell). Parse JSON `{"text": "..."}`.
- LLM cleanup (replicates `stt-postprocess.sh`), two providers selected by `settings.provider`:
  - `lmstudio` → `POST settings.lmStudioURL`, body `{model, input, store:false, stream:false, reasoning, temperature}`; response text = concatenation of `output[].content` where `output[].type == "message"`.
  - `openai` → `POST settings.lmStudioURL`, body `{model, messages:[{role:"system",content:prompt},{role:"user",content:transcript}], stream:false, temperature}`; response text = `choices[0].message.content`.
- `SttMode` semantics: `.full` = LLM cleanup, source language; `.raw` = skip LLM (replacements still apply); `.english` = LLM cleanup with output translated to English (append a translation instruction to the prompt).
- Replacements (`ReplacementStore.preview(_:)`) apply to the final text in all modes (including `.raw`).
- On any transcription/LLM failure, surface a clear error via the existing `Result.failure` path the Phase-1 `SttRunner` already handles; on LLM failure when `.full`/`.english`, fall back to the raw (replacements-only) transcript rather than losing the text (matches `STT_AUTO_RAW_FALLBACK=1`).
- Microphone permission must be requested before the first recording (`AVCaptureDevice.requestAccess(for: .audio)` / existing `Permissions.requestMicrophone()`).
- All work happens on branch `feature/app-store-phase2-native-pipeline`, branched from `feature/app-store-phase1-sandbox` (Phase 1 must land first).

---

### Task 0: Branch from Phase 1

**Files:** none (git only)

- [ ] **Step 1: Branch off the Phase 1 branch**

```bash
cd /Users/simon-danielmarz/Documents/GitHub/STTBar
git checkout feature/app-store-phase1-sandbox
git checkout -b feature/app-store-phase2-native-pipeline
```

- [ ] **Step 2: Confirm baseline build**

Run: `swift build --package-path macos-app`
Expected: Build complete.

---

### Task 1: `TranscriptionConfig` value struct

**Files:**
- Create: `macos-app/Sources/STTBar/Core/Transcription/TranscriptionConfig.swift`
- Test: `macos-app/Tests/STTBarTests/TranscriptionConfigTests.swift`

**Interfaces:**
- Produces: `struct TranscriptionConfig { whisperURL, whisperModel, language: String; postprocessEnabled: Bool; provider, lmStudioURL, llmModel, promptBody: String; transcribeTimeout, postprocessTimeout: TimeInterval; temperature: Double; reasoning: String }` plus `static func from(_ model: SettingsModel) -> TranscriptionConfig`.
- Consumed by: `WhisperClient`, `LLMClient`, `NativeBackend`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import STTBar

final class TranscriptionConfigTests: XCTestCase {
    func testLanguageOmittedWhenAuto() {
        XCTAssertNil(TranscriptionConfig.languageParam(for: "auto"))
        XCTAssertEqual(TranscriptionConfig.languageParam(for: "de"), "de")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path macos-app --filter TranscriptionConfigTests`
Expected: FAIL — type does not exist.

- [ ] **Step 3: Create `TranscriptionConfig.swift`**

```swift
import Foundation

/// Immutable snapshot of the settings the native pipeline needs for one run.
struct TranscriptionConfig {
    var whisperURL: String
    var whisperModel: String
    var language: String
    var postprocessEnabled: Bool
    var provider: String
    var lmStudioURL: String
    var llmModel: String
    var promptBody: String
    var transcribeTimeout: TimeInterval
    var postprocessTimeout: TimeInterval
    var temperature: Double
    var reasoning: String

    /// The Whisper `language` form field, or nil when auto-detect is requested.
    static func languageParam(for language: String) -> String? {
        let v = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v.isEmpty || v.lowercased() == "auto") ? nil : v
    }

    @MainActor
    static func from(_ model: SettingsModel) -> TranscriptionConfig {
        TranscriptionConfig(
            whisperURL: model.whisperURL,
            whisperModel: model.whisperModel,
            language: model.language,
            postprocessEnabled: model.postprocessEnabled,
            provider: model.provider,
            lmStudioURL: model.lmStudioURL,
            llmModel: model.llmModel,
            promptBody: model.prompts.activePrompt?.body ?? "",
            transcribeTimeout: TimeInterval(Int(model.postprocessTimeout) ?? 30),
            postprocessTimeout: TimeInterval(Int(model.postprocessTimeout) ?? 60),
            temperature: 0,
            reasoning: "off")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path macos-app --filter TranscriptionConfigTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Sources/STTBar/Core/Transcription/TranscriptionConfig.swift macos-app/Tests/STTBarTests/TranscriptionConfigTests.swift
git commit -m "feat(app-store): add TranscriptionConfig settings snapshot"
```

---

### Task 2: `WhisperClient` — multipart upload request builder

**Files:**
- Create: `macos-app/Sources/STTBar/Core/Transcription/WhisperClient.swift`
- Test: `macos-app/Tests/STTBarTests/WhisperClientTests.swift`

**Interfaces:**
- Produces: `struct WhisperClient { func makeRequest(audioURL: URL, config: TranscriptionConfig, boundary: String) -> URLRequest?; func multipartBody(audioData: Data, filename: String, config: TranscriptionConfig, boundary: String) -> Data; static func parseText(_ data: Data) -> String?; func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String }`.
- Consumed by: `NativeBackend`.

- [ ] **Step 1: Write the failing test (request + body shape + parse, no network)**

```swift
import XCTest
@testable import STTBar

final class WhisperClientTests: XCTestCase {
    private func cfg(language: String) -> TranscriptionConfig {
        TranscriptionConfig(whisperURL: "http://localhost:8000/v1/audio/transcriptions",
                            whisperModel: "Systran/faster-whisper-base", language: language,
                            postprocessEnabled: false, provider: "lmstudio", lmStudioURL: "",
                            llmModel: "", promptBody: "", transcribeTimeout: 30,
                            postprocessTimeout: 60, temperature: 0, reasoning: "off")
    }

    func testBodyIncludesModelAndResponseFormatAndLanguage() {
        let body = WhisperClient().multipartBody(audioData: Data([0x52, 0x49, 0x46, 0x46]),
            filename: "recording.wav", config: cfg(language: "de"), boundary: "B")
        let s = String(data: body, encoding: .ascii) ?? ""
        XCTAssertTrue(s.contains("name=\"model\"\r\n\r\nSystran/faster-whisper-base"))
        XCTAssertTrue(s.contains("name=\"response_format\"\r\n\r\njson"))
        XCTAssertTrue(s.contains("name=\"language\"\r\n\r\nde"))
        XCTAssertTrue(s.contains("name=\"file\"; filename=\"recording.wav\""))
    }

    func testBodyOmitsLanguageWhenAuto() {
        let body = WhisperClient().multipartBody(audioData: Data([0x00]),
            filename: "r.wav", config: cfg(language: "auto"), boundary: "B")
        let s = String(data: body, encoding: .ascii) ?? ""
        XCTAssertFalse(s.contains("name=\"language\""))
    }

    func testParseTextReadsTextField() {
        let json = #"{"text":"hallo welt"}"#.data(using: .utf8)!
        XCTAssertEqual(WhisperClient.parseText(json), "hallo welt")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path macos-app --filter WhisperClientTests`
Expected: FAIL — `WhisperClient` does not exist.

- [ ] **Step 3: Create `WhisperClient.swift`**

```swift
import Foundation

enum WhisperError: LocalizedError {
    case badURL, http(Int, String), noText
    var errorDescription: String? {
        switch self {
        case .badURL: return L("Ungültige Whisper-URL.", "Invalid Whisper URL.")
        case .http(let code, let body): return L("Whisper-Fehler (HTTP \(code)).", "Whisper error (HTTP \(code)).") + (body.isEmpty ? "" : " \(body.prefix(200))")
        case .noText: return L("Whisper lieferte keinen Text.", "Whisper returned no text.")
        }
    }
}

/// Uploads a WAV to a Whisper-compatible endpoint (replaces stt-transcribe.sh).
struct WhisperClient {
    var session: URLSession = .shared

    func multipartBody(audioData: Data, filename: String, config: TranscriptionConfig, boundary: String) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        // file part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        field("model", config.whisperModel)
        field("response_format", "json")
        if let lang = TranscriptionConfig.languageParam(for: config.language) { field("language", lang) }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    func makeRequest(audioURL: URL, config: TranscriptionConfig, boundary: String) -> URLRequest? {
        guard let url = URL(string: config.whisperURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = config.transcribeTimeout
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return req
    }

    static func parseText(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let text = (obj["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String {
        let boundary = "STTBar-\(UUID().uuidString)"
        guard var req = makeRequest(audioURL: audioURL, config: config, boundary: boundary) else { throw WhisperError.badURL }
        let audioData = try Data(contentsOf: audioURL)
        req.httpBody = multipartBody(audioData: audioData, filename: audioURL.lastPathComponent, config: config, boundary: boundary)
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw WhisperError.http(code, String(data: data, encoding: .utf8) ?? "") }
        guard let text = Self.parseText(data) else { throw WhisperError.noText }
        return text
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path macos-app --filter WhisperClientTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Sources/STTBar/Core/Transcription/WhisperClient.swift macos-app/Tests/STTBarTests/WhisperClientTests.swift
git commit -m "feat(app-store): native Whisper multipart client (replaces stt-transcribe.sh)"
```

---

### Task 3: `LLMClient` — two-provider cleanup request builder

**Files:**
- Create: `macos-app/Sources/STTBar/Core/Transcription/LLMClient.swift`
- Test: `macos-app/Tests/STTBarTests/LLMClientTests.swift`

**Interfaces:**
- Produces: `struct LLMClient { static func body(provider: String, model: String, prompt: String, transcript: String, temperature: Double, reasoning: String) -> Data; static func parse(provider: String, _ data: Data) -> String?; func clean(transcript: String, config: TranscriptionConfig, translateTo: String?) async throws -> String }`.
- Consumed by: `NativeBackend`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import STTBar

final class LLMClientTests: XCTestCase {
    func testOpenAIBodyHasSystemAndUserMessages() {
        let data = LLMClient.body(provider: "openai", model: "m", prompt: "SYS", transcript: "USR", temperature: 0, reasoning: "off")
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let messages = obj["messages"] as! [[String: String]]
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "SYS")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "USR")
    }

    func testLMStudioBodyUsesInputField() {
        let data = LLMClient.body(provider: "lmstudio", model: "m", prompt: "SYS", transcript: "USR", temperature: 0, reasoning: "off")
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(obj["input"])
        XCTAssertEqual(obj["stream"] as? Bool, false)
    }

    func testParseOpenAIResponse() {
        let json = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        XCTAssertEqual(LLMClient.parse(provider: "openai", json), "ok")
    }

    func testParseLMStudioResponse() {
        let json = #"{"output":[{"type":"message","content":"ok"}]}"#.data(using: .utf8)!
        XCTAssertEqual(LLMClient.parse(provider: "lmstudio", json), "ok")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path macos-app --filter LLMClientTests`
Expected: FAIL.

- [ ] **Step 3: Create `LLMClient.swift`**

```swift
import Foundation

enum LLMError: LocalizedError {
    case badURL, http(Int), empty
    var errorDescription: String? {
        switch self {
        case .badURL: return L("Ungültige LLM-URL.", "Invalid LLM URL.")
        case .http(let c): return L("LLM-Fehler (HTTP \(c)).", "LLM error (HTTP \(c)).")
        case .empty: return L("LLM lieferte keinen Text.", "LLM returned no text.")
        }
    }
}

/// Optional LLM cleanup (replaces stt-postprocess.sh). Supports the LM Studio
/// `input` shape and the OpenAI `messages` shape.
struct LLMClient {
    var session: URLSession = .shared

    static func body(provider: String, model: String, prompt: String, transcript: String, temperature: Double, reasoning: String) -> Data {
        let obj: [String: Any]
        if provider == "openai" {
            obj = ["model": model,
                   "messages": [["role": "system", "content": prompt],
                                ["role": "user", "content": transcript]],
                   "stream": false,
                   "temperature": temperature]
        } else {
            obj = ["model": model,
                   "input": prompt + "\n\n" + transcript,
                   "store": false,
                   "stream": false,
                   "reasoning": reasoning,
                   "temperature": temperature]
        }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    static func parse(provider: String, _ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let text: String?
        if provider == "openai" {
            let choices = obj["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
        } else {
            let output = obj["output"] as? [[String: Any]] ?? []
            text = output.filter { ($0["type"] as? String) == "message" }
                         .compactMap { $0["content"] as? String }.joined()
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    func clean(transcript: String, config: TranscriptionConfig, translateTo: String?) async throws -> String {
        guard let url = URL(string: config.lmStudioURL) else { throw LLMError.badURL }
        var prompt = config.promptBody
        if let lang = translateTo {
            prompt += "\n\n" + L("Übersetze die Ausgabe nach \(lang). Behalte alle anderen Regeln bei.",
                                 "Translate the output to \(lang). Keep all other rules.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = config.postprocessTimeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.body(provider: config.provider, model: config.llmModel, prompt: prompt,
                                 transcript: transcript, temperature: config.temperature, reasoning: config.reasoning)
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw LLMError.http(code) }
        guard let text = Self.parse(provider: config.provider, data) else { throw LLMError.empty }
        return text
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path macos-app --filter LLMClientTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Sources/STTBar/Core/Transcription/LLMClient.swift macos-app/Tests/STTBarTests/LLMClientTests.swift
git commit -m "feat(app-store): native LLM cleanup client (replaces stt-postprocess.sh)"
```

---

### Task 4: `AudioRecorder` — AVAudioEngine → 16 kHz mono WAV

**Files:**
- Create: `macos-app/Sources/STTBar/Core/Transcription/AudioRecorder.swift`
- Test: `macos-app/Tests/STTBarTests/AudioRecorderTests.swift`

**Interfaces:**
- Produces: `final class AudioRecorder { var isRecording: Bool { get }; func start(outputURL: URL) throws; func stop() -> URL?; func cancel() }` writing a 16 kHz mono 16-bit WAV.
- Consumed by: `NativeBackend`. Writes to `RuntimePaths.recordingFile` so the HUD's `AudioLevelReader` works unchanged.

- [ ] **Step 1: Write the failing test (format constants are pure/testable; engine I/O is not unit-tested)**

```swift
import XCTest
import AVFoundation
@testable import STTBar

final class AudioRecorderTests: XCTestCase {
    func testTargetFormatIs16kMono16bit() {
        let fmt = AudioRecorder.targetSettings
        XCTAssertEqual(fmt[AVSampleRateKey] as? Int, 16000)
        XCTAssertEqual(fmt[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(fmt[AVLinearPCMBitDepthKey] as? Int, 16)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path macos-app --filter AudioRecorderTests`
Expected: FAIL.

- [ ] **Step 3: Create `AudioRecorder.swift`**

```swift
import AVFoundation

enum AudioRecorderError: LocalizedError {
    case engineStart(String)
    var errorDescription: String? {
        switch self {
        case .engineStart(let m): return L("Audio-Engine konnte nicht starten.", "Audio engine could not start.") + " \(m)"
        }
    }
}

/// Records microphone audio as a 16 kHz mono 16-bit WAV (replaces stt-record.sh).
/// Writes to `outputURL` so the HUD AudioLevelReader can tail the same file.
final class AudioRecorder {
    static let targetSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var isRecording = false
    private var outputURL: URL?

    func start(outputURL: URL) throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(settings: Self.targetSettings)!
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        file = try AVAudioFile(forWriting: outputURL, settings: Self.targetSettings,
                               commonFormat: .pcmFormatInt16, interleaved: true)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter, let file = self.file else { return }
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            if error == nil, out.frameLength > 0 { try? file.write(from: out) }
        }

        engine.prepare()
        do { try engine.start() } catch { throw AudioRecorderError.engineStart(error.localizedDescription) }
        isRecording = true
    }

    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        file = nil           // close + flush the WAV
        converter = nil
        return outputURL
    }

    func cancel() {
        _ = stop()
        if let url = outputURL { try? FileManager.default.removeItem(at: url) }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path macos-app --filter AudioRecorderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Sources/STTBar/Core/Transcription/AudioRecorder.swift macos-app/Tests/STTBarTests/AudioRecorderTests.swift
git commit -m "feat(app-store): native AVAudioEngine recorder (replaces stt-record.sh)"
```

---

### Task 5: `NativeBackend` — orchestrate record → transcribe → clean → replace

**Files:**
- Create: `macos-app/Sources/STTBar/Core/Transcription/NativeBackend.swift`
- Test: `macos-app/Tests/STTBarTests/NativeBackendTests.swift`

**Interfaces:**
- Produces: `final class NativeBackend: TranscriptionBackend` with `init(config: @escaping () -> TranscriptionConfig, replace: @escaping (String) -> String, recorder: AudioRecorder = .init(), whisper: WhisperClient = .init(), llm: LLMClient = .init())`.
- Consumes: the Phase-1 `TranscriptionBackend` protocol (`isRecording`, `start(mode:)`, `stop(mode:completion:)`, `cancel()`), `RuntimePaths.recordingFile`.
- Mode mapping (pure, testable): `static func usesLLM(_ mode: SttMode) -> Bool` (true for `.full`/`.english`), `static func translateTarget(_ mode: SttMode) -> String?` (`"English"` for `.english`, else nil).

- [ ] **Step 1: Write the failing test (pure mode mapping)**

```swift
import XCTest
@testable import STTBar

final class NativeBackendTests: XCTestCase {
    func testModeMapping() {
        XCTAssertTrue(NativeBackend.usesLLM(.full))
        XCTAssertTrue(NativeBackend.usesLLM(.english))
        XCTAssertFalse(NativeBackend.usesLLM(.raw))
        XCTAssertEqual(NativeBackend.translateTarget(.english), "English")
        XCTAssertNil(NativeBackend.translateTarget(.full))
        XCTAssertNil(NativeBackend.translateTarget(.raw))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path macos-app --filter NativeBackendTests`
Expected: FAIL.

- [ ] **Step 3: Create `NativeBackend.swift`**

```swift
import Foundation

/// Native record→transcribe→clean→replace pipeline behind the Phase-1
/// TranscriptionBackend seam. Server mode (remote/self-host Whisper).
final class NativeBackend: TranscriptionBackend {
    private let configProvider: () -> TranscriptionConfig
    private let replace: (String) -> String
    private let recorder: AudioRecorder
    private let whisper: WhisperClient
    private let llm: LLMClient

    init(config: @escaping () -> TranscriptionConfig,
         replace: @escaping (String) -> String,
         recorder: AudioRecorder = AudioRecorder(),
         whisper: WhisperClient = WhisperClient(),
         llm: LLMClient = LLMClient()) {
        self.configProvider = config
        self.replace = replace
        self.recorder = recorder
        self.whisper = whisper
        self.llm = llm
    }

    var isRecording: Bool { recorder.isRecording }

    static func usesLLM(_ mode: SttMode) -> Bool { mode == .full || mode == .english }
    static func translateTarget(_ mode: SttMode) -> String? { mode == .english ? "English" : nil }

    func start(mode: SttMode) throws {
        RuntimePaths.ensureDirectory()
        try recorder.start(outputURL: RuntimePaths.recordingFile)
    }

    func cancel() { recorder.cancel() }

    func stop(mode: SttMode, completion: @escaping (Result<String, Error>) -> Void) {
        guard let audioURL = recorder.stop() else { completion(.success("")); return }
        let config = configProvider()
        Task {
            do {
                let raw = try await whisper.transcribe(audioURL: audioURL, config: config)
                var text = raw
                if Self.usesLLM(mode) && config.postprocessEnabled {
                    do {
                        text = try await llm.clean(transcript: raw, config: config, translateTo: Self.translateTarget(mode))
                    } catch {
                        // STT_AUTO_RAW_FALLBACK: keep the raw transcript on LLM failure.
                        AppLogger.log("llm_cleanup_failed_fallback_raw \(error.localizedDescription)")
                        text = raw
                    }
                }
                let final = replace(text)
                completion(.success(final))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path macos-app --filter NativeBackendTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Sources/STTBar/Core/Transcription/NativeBackend.swift macos-app/Tests/STTBarTests/NativeBackendTests.swift
git commit -m "feat(app-store): NativeBackend orchestrates the native pipeline"
```

---

### Task 6: Wire `NativeBackend` into `AppDelegate`; request microphone

**Files:**
- Modify: `macos-app/Sources/STTBar/AppDelegate.swift`

**Interfaces:**
- Consumes: `NativeBackend(config:replace:)` (Task 5), `TranscriptionConfig.from(_:)` (Task 1), `SettingsModel`, `Permissions.requestMicrophone()`.
- The model must be created BEFORE the runner so the backend can read it. Reorder so `model = SettingsModel(installDir:)` precedes `runner = SttRunner(backend:)`.

- [ ] **Step 1: Reorder + inject the backend**

In `applicationDidFinishLaunching`, replace the existing `runner = SttRunner()` / `model = SettingsModel(installDir: installDir)` ordering with model-first, then:

```swift
        try? FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        model = SettingsModel(installDir: installDir)
        let backend = NativeBackend(
            config: { [weak self] in
                guard let self else { return TranscriptionConfig.from(self!.model) }
                return MainActor.assumeIsolated { TranscriptionConfig.from(self.model) }
            },
            replace: { [weak self] text in self?.model.replacements.preview(text) ?? text })
        runner = SttRunner(backend: backend)
```

(If the `MainActor.assumeIsolated` closure proves awkward, drop the `@MainActor` on `TranscriptionConfig.from` — the read is main-thread in practice; verified by the build in Step 2.)

- [ ] **Step 2: Request microphone access at launch**

After `hotkeys.install()`, add:

```swift
        Permissions.requestMicrophone()
```

- [ ] **Step 3: Build**

Run: `swift build --package-path macos-app`
Expected: Build complete.

- [ ] **Step 4: Run the full suite**

Run: `swift test --package-path macos-app`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Sources/STTBar/AppDelegate.swift
git commit -m "feat(app-store): wire NativeBackend into the app, request microphone"
```

---

### Task 7: Honor the audio-input device picker

**Files:**
- Modify: `macos-app/Sources/STTBar/Core/Transcription/AudioRecorder.swift`
- Modify: `macos-app/Sources/STTBar/Core/Transcription/TranscriptionConfig.swift` (add `audioDevice: String`)

**Interfaces:**
- The existing `AudioInputDevices.available()` returns `localizedName`s and the picker stores one in `SettingsModel.audioInputDevice`. Map that name to a CoreAudio `AudioDeviceID` and set it on the engine input node's audio unit via `kAudioOutputUnitProperty_CurrentDevice`. Empty string = system default (no override).

- [ ] **Step 1: Add device lookup + apply on the engine**

Add to `AudioRecorder` (before `engine.prepare()` in `start`): if `device` non-empty, resolve the `AudioDeviceID` whose name matches and set it:

```swift
    private func applyInputDevice(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let deviceID = Self.audioDeviceID(named: name) else { return }
        var id = deviceID
        let unit = engine.inputNode.audioUnit
        if let unit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
    }
```

with a `static func audioDeviceID(named:) -> AudioDeviceID?` that enumerates `kAudioHardwarePropertyDevices` and matches `kAudioObjectPropertyName`. Pass `config.audioDevice` into `start`.

- [ ] **Step 2: Build + smoke test recording with a non-default device selected**

Run: `swift build --package-path macos-app`
Expected: Build complete. (Runtime device selection verified manually in Task 8.)

- [ ] **Step 3: Commit**

```bash
git add macos-app/Sources/STTBar/Core/Transcription/AudioRecorder.swift macos-app/Sources/STTBar/Core/Transcription/TranscriptionConfig.swift
git commit -m "feat(app-store): honor the audio-input device picker in the native recorder"
```

---

### Task 8: End-to-end manual verification (server mode)

**Files:** none (runtime verification)

- [ ] **Step 1: Build, quit the production app, launch the sandboxed build**

```bash
bash macos-app/build-app.sh /tmp/sttbar-phase2
# Quit the running production STTBar from the menu bar first.
open /tmp/sttbar-phase2/STTBar.app
```

- [ ] **Step 2: Configure a reachable Whisper endpoint and dictate**

In Settings, set the Whisper URL/model to a reachable server. Trigger the hotkey, speak, trigger again. Expected: the HUD shows the waveform during recording, then "whisper" phase, then the transcript is pasted into the focused field. Confirm `~/Library/Containers/de.projectmakers.sttbar/Data/Library/Application Support/STTBar/runtime/recording.wav` exists and is 16 kHz mono.

- [ ] **Step 3: Test raw mode + LLM mode + replacements**

Trigger raw-mode hotkey (no LLM), then full-mode (LLM on, reachable endpoint), and confirm a configured replacement is applied in both.

- [ ] **Step 4: Update the board**

```bash
python3 ~/.claude/skills/horizon-kanban/scripts/kanban.py comment TASK-350 --text "Phase 2 (native Pipeline, Server-Modus) fertig: AVAudioEngine-Aufnahme (16k mono WAV), URLSession-Whisper-Upload, optionaler LLM-Cleanup (lmstudio+openai), Replacements, Gerätewahl. Server-Modus läuft Ende-zu-Ende ohne Shell."
```

---

## Self-Review

**Spec coverage (Phase 2 acceptance criteria):**
- Recording via AVAudioEngine/AVAudioRecorder → Task 4. ✅
- HUD waveform fed from native audio → recorder writes the same WAV the existing `AudioLevelReader` tails (Global Constraints + Task 4). ✅
- Transcription via URLSession multipart → Task 2. ✅
- Optional LLM cleanup via URLSession; Ollama/LM-Studio links only → Task 3 (links are a Phase 4 Settings item). ✅
- Server mode end-to-end without shell → Tasks 5–6 + manual Task 8. ✅
- Device picker honored → Task 7. ✅

**Placeholder scan:** Task 7's CoreAudio lookup is described with the exact API (`kAudioOutputUnitProperty_CurrentDevice`, `kAudioHardwarePropertyDevices`, `kAudioObjectPropertyName`) rather than full enumeration boilerplate — acceptable as it is a well-known idiom, but the implementer should expand `audioDeviceID(named:)` fully. All other steps contain complete code.

**Type consistency:** `TranscriptionConfig` fields are referenced identically across `WhisperClient`, `LLMClient`, `NativeBackend`. `TranscriptionBackend` members match the Phase-1 protocol. `NativeBackend.usesLLM`/`translateTarget` are used consistently in the orchestration.

**Open follow-ups (not Phase 2 blockers):**
- No API-key/Authorization field exists today (shell sent none); add an optional Bearer field when an endpoint needs auth (Settings work, fits Phase 4).
- The shell's perl URL/email/path fixup is not ported; `ReplacementStore.preview` covers configured replacements. Port the fixups later if needed.
- `transcribeTimeout` currently reuses the postprocess timeout default of 30; add a dedicated setting if the 30 s default proves too tight.
