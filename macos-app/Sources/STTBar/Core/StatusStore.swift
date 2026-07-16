import Foundation

struct SttStatus: Codable, Equatable {
    var schema: Int?
    var timestamp: String?
    var runId: String?
    var event: String
    var phase: String
    var severity: String
    var code: String?
    var message: String
    var detail: String?
    var audioFile: String?
    var resultFile: String?

    enum CodingKeys: String, CodingKey {
        case schema, timestamp, event, phase, severity, code, message, detail
        case runId = "run_id"
        case audioFile = "audio_file"
        case resultFile = "result_file"
    }
}

struct RunMetric: Codable, Identifiable, Equatable {
    var id: String { runId ?? timestamp ?? UUID().uuidString }
    var schema: Int?
    var timestamp: String?
    var runId: String?
    var mode: String?
    var wavBytes: Int?
    var recordingMs: Int?
    var whisperMs: Int?
    var whisperTextChars: Int?
    var postprocessMs: Int?
    var outputChars: Int?
    var pasteStatus: String?

    enum CodingKeys: String, CodingKey {
        case schema, timestamp, mode
        case runId = "run_id"
        case wavBytes = "wav_bytes"
        case recordingMs = "recording_ms"
        case whisperMs = "whisper_ms"
        case whisperTextChars = "whisper_text_chars"
        case postprocessMs = "postprocess_ms"
        case outputChars = "output_chars"
        case pasteStatus = "paste_status"
    }
}

enum StatusStore {
    static func readCurrent() -> SttStatus? {
        decode(SttStatus.self, from: RuntimePaths.statusFile)
    }

    static func latestProblem(limit: Int = 200) -> SttStatus? {
        let events = readEvents(limit: limit)
        return events.reversed().first { $0.severity == "error" || $0.severity == "warning" }
    }

    static func readEvents(limit: Int = 200) -> [SttStatus] {
        guard let text = LineJournal.tail(of: RuntimePaths.eventsFile) else { return [] }
        let lines = text.split(separator: "\n").suffix(limit)
        return lines.compactMap { line in
            try? JSONDecoder().decode(SttStatus.self, from: Data(line.utf8))
        }
    }

    static func readMetrics(limit: Int = 20) -> [RunMetric] {
        guard let text = LineJournal.tail(of: RuntimePaths.metricsFile) else { return [] }
        let lines = text.split(separator: "\n").suffix(limit)
        return lines.compactMap { line in
            try? JSONDecoder().decode(RunMetric.self, from: Data(line.utf8))
        }.reversed()
    }

    /// Appends one run's metrics as a JSON line, matching the shell backend's
    /// metrics.jsonl format so the menu tooltip and Status window can read the
    /// native pipeline's timings the same way.
    static func appendRunMetric(_ metric: RunMetric) {
        RuntimePaths.ensureDirectory()
        guard let data = try? JSONEncoder().encode(metric),
              let line = String(data: data, encoding: .utf8) else { return }
        LineJournal.append(line + "\n", to: RuntimePaths.metricsFile)
    }

    static func writeAppStatus(event: String, phase: String, severity: String, code: String = "", message: String, detail: String = "") {
        RuntimePaths.ensureDirectory()
        let status = SttStatus(schema: 1,
                               timestamp: ISO8601DateFormatter().string(from: Date()),
                               runId: nil,
                               event: event,
                               phase: phase,
                               severity: severity,
                               code: code,
                               message: message,
                               detail: detail,
                               audioFile: RuntimePaths.recordingFile.path,
                               resultFile: RuntimePaths.resultFile.path)
        guard let data = try? JSONEncoder().encode(status) else { return }
        try? data.write(to: RuntimePaths.statusFile, options: .atomic)
        if let line = String(data: data, encoding: .utf8) {
            append(line + "\n", to: RuntimePaths.eventsFile)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func append(_ text: String, to url: URL) {
        RuntimePaths.ensureDirectory()
        LineJournal.append(text, to: url)
    }
}
