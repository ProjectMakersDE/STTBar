import XCTest
@testable import STTBar

private func makeConfig(whisperKey: String = "", llmKey: String = "",
                        llmURL: String = "https://openrouter.ai/api/v1/chat/completions") -> TranscriptionConfig {
    TranscriptionConfig(whisperURL: "https://whisper.example.com/v1/audio/transcriptions",
                        whisperModel: "Systran/faster-whisper-base", language: "de",
                        postprocessEnabled: true, provider: "openai", lmStudioURL: llmURL,
                        llmModel: "m", promptBody: "SYS", transcribeTimeout: 30,
                        postprocessTimeout: 60, temperature: 0, reasoning: "off",
                        replacements: ReplacementStore(directory: FileManager.default.temporaryDirectory),
                        source: "server", localModel: "",
                        whisperAPIKey: whisperKey, llmAPIKey: llmKey)
}

final class ApiKeyStoreTests: XCTestCase {
    func testAccountIsTheLowercasedHostWithExplicitPort() {
        XCTAssertEqual(ApiKeyStore.account(for: "https://OpenRouter.ai/api/v1/chat/completions"), "openrouter.ai")
        XCTAssertEqual(ApiKeyStore.account(for: "http://localhost:1234/api/v1/chat"), "localhost:1234")
        XCTAssertEqual(ApiKeyStore.account(for: " https://api.openai.com/v1/audio/transcriptions "), "api.openai.com")
    }

    func testAccountRejectsAnythingButHttpWithAHost() {
        XCTAssertNil(ApiKeyStore.account(for: ""))
        XCTAssertNil(ApiKeyStore.account(for: "not a url"))
        XCTAssertNil(ApiKeyStore.account(for: "ftp://files.example.com/x"))
        XCTAssertNil(ApiKeyStore.account(for: "https://"))
    }

    func testAuthorizeSetsABearerHeaderOnlyForANonEmptyKey() {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        ApiKeyStore.authorize(&request, key: "  ")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        ApiKeyStore.authorize(&request, key: " sk-test ")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }
}

final class ApiKeyRequestTests: XCTestCase {
    func testWhisperRequestCarriesTheKey() {
        let request = WhisperClient().makeRequest(config: makeConfig(whisperKey: "sk-whisper"), boundary: "B")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-whisper")
    }

    func testWhisperRequestWithoutKeyHasNoAuthorization() {
        let request = WhisperClient().makeRequest(config: makeConfig(), boundary: "B")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
    }

    func testLLMRequestCarriesTheKeyAndTheOpenAIBody() throws {
        let request = try XCTUnwrap(LLMClient.makeRequest(transcript: "USR", config: makeConfig(llmKey: "sk-or"), translateTo: nil))
        XCTAssertEqual(request.url?.absoluteString, LLMClient.openRouterURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertNotNil(obj["messages"])
    }

    func testLLMRequestWithoutKeyHasNoAuthorization() {
        let request = LLMClient.makeRequest(transcript: "USR", config: makeConfig(llmURL: "http://localhost:1234/v1/chat/completions"), translateTo: nil)
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
    }

    func testChatCompletionsURLsInferTheOpenAIProvider() {
        XCTAssertEqual(LLMClient.inferredProvider(for: LLMClient.openRouterURL), "openai")
        XCTAssertEqual(LLMClient.inferredProvider(for: "http://localhost:1234/v1/chat/completions"), "openai")
        XCTAssertNil(LLMClient.inferredProvider(for: "http://localhost:1234/api/v1/chat"))
    }
}

/// Answers like OpenRouter and remembers what reached it.
private final class OpenRouterStub: URLProtocol {
    static var authorization: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.authorization = request.value(forHTTPHeaderField: "Authorization")
        let ok = Self.authorization == "Bearer sk-or"
        let body = ok ? #"{"choices":[{"message":{"role":"assistant","content":"Den Login-Flow umbauen."}}]}"#
                      : #"{"error":{"code":401,"message":"No auth credentials found"}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: ok ? 200 : 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class LLMClientAuthTests: XCTestCase {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenRouterStub.self]
        return URLSession(configuration: configuration)
    }

    func testCleanSendsTheKeyAndReadsTheAnswer() async throws {
        let text = try await LLMClient(session: session()).clean(transcript: "äh den login flow umbauen",
                                                                 config: makeConfig(llmKey: "sk-or"), translateTo: nil)
        XCTAssertEqual(OpenRouterStub.authorization, "Bearer sk-or")
        XCTAssertEqual(text, "Den Login-Flow umbauen.")
    }

    func testCleanWithoutKeySurfacesTheHTTPError() async {
        do {
            _ = try await LLMClient(session: session()).clean(transcript: "x", config: makeConfig(), translateTo: nil)
            XCTFail("expected an HTTP error")
        } catch LLMError.http(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
