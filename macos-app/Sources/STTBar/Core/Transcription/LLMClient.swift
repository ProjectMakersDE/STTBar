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

    static let openRouterURL = "https://openrouter.ai/api/v1/chat/completions"

    /// `/chat/completions` is the OpenAI route by definition (LM Studio serves
    /// it too), so such a URL always wants the `messages` shape.
    static func inferredProvider(for urlString: String) -> String? {
        guard let path = URLComponents(string: urlString)?.path.lowercased() else { return nil }
        return path.hasSuffix("/chat/completions") ? "openai" : nil
    }

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

    static func makeRequest(transcript: String, config: TranscriptionConfig, translateTo: String?) -> URLRequest? {
        guard let url = URL(string: config.lmStudioURL) else { return nil }
        var prompt = config.promptBody
        if let lang = translateTo {
            prompt += "\n\n" + L("Übersetze die Ausgabe nach \(lang). Behalte alle anderen Regeln bei.",
                                 "Translate the output to \(lang). Keep all other rules.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = config.postprocessTimeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ApiKeyStore.authorize(&req, key: config.llmAPIKey)
        req.httpBody = body(provider: config.provider, model: config.llmModel, prompt: prompt,
                            transcript: transcript, temperature: config.temperature, reasoning: config.reasoning)
        return req
    }

    func clean(transcript: String, config: TranscriptionConfig, translateTo: String?) async throws -> String {
        guard let req = Self.makeRequest(transcript: transcript, config: config, translateTo: translateTo) else { throw LLMError.badURL }
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw LLMError.http(code) }
        guard let text = Self.parse(provider: config.provider, data) else { throw LLMError.empty }
        return text
    }
}
