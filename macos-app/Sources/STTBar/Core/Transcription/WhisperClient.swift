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
        if let prompt = TranscriptionConfig.promptParam(for: config.whisperPrompt, language: config.language) { field("prompt", prompt) }
        if config.vadFilter { field("vad_filter", "true") }
        if let beam = TranscriptionConfig.beamSizeParam(for: config.beamSize) { field("beam_size", beam) }
        if !config.temperatureFallback {
            field("temperature", "0")
            field("temperature_inc", "0")
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    func makeRequest(config: TranscriptionConfig, boundary: String) -> URLRequest? {
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

    /// Some servers echo the `prompt` at the start of the transcript. Drop it
    /// (case-insensitively) so the conditioning sentence never gets pasted.
    static func stripEchoedPrompt(_ text: String, prompt: String?) -> String {
        guard let prompt, !prompt.isEmpty else { return text }
        guard text.count >= prompt.count else { return text }
        let head = String(text.prefix(prompt.count))
        guard head.compare(prompt, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else { return text }
        return String(text.dropFirst(prompt.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String {
        let boundary = "STTBar-\(UUID().uuidString)"
        guard var req = makeRequest(config: config, boundary: boundary) else { throw WhisperError.badURL }
        let audioData = try Data(contentsOf: audioURL)
        req.httpBody = multipartBody(audioData: audioData, filename: audioURL.lastPathComponent, config: config, boundary: boundary)
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw WhisperError.http(code, String(data: data, encoding: .utf8) ?? "") }
        guard let raw = Self.parseText(data) else { throw WhisperError.noText }
        let text = Self.stripEchoedPrompt(raw, prompt: TranscriptionConfig.promptParam(for: config.whisperPrompt, language: config.language))
        guard !text.isEmpty else { throw WhisperError.noText }
        return text
    }
}
