import Foundation

enum RuntimePaths {
    static var directory: URL {
        if let custom = ProcessInfo.processInfo.environment["STT_RUNTIME_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        return URL(fileURLWithPath: base).appendingPathComponent("de.projectmakers.stt", isDirectory: true)
    }

    static var phaseFile: URL { directory.appendingPathComponent("phase") }
    static var statusFile: URL { directory.appendingPathComponent("status.json") }
    static var eventsFile: URL { directory.appendingPathComponent("events.jsonl") }
    static var metricsFile: URL { directory.appendingPathComponent("metrics.jsonl") }
    static var resultFile: URL { directory.appendingPathComponent("last-transcript.txt") }
    static var pidFile: URL { directory.appendingPathComponent("recording.pid") }
    static var recordingFile: URL { directory.appendingPathComponent("recording.wav") }
    static var lockFile: URL { directory.appendingPathComponent("recording.lock") }
    static var recordingStartedFile: URL { directory.appendingPathComponent("recording-started-ms") }
    static var legacyPidFile: URL { URL(fileURLWithPath: "/tmp/stt-recording.pid") }
    static var legacyRecordingFile: URL { URL(fileURLWithPath: "/tmp/stt-recording.wav") }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
