import Foundation

enum RuntimePaths {
    /// Runtime scratch lives in the sandbox container's Application Support
    /// (`~/Library/Containers/de.projectmakers.sttbar/Data/Library/Application Support/STTBar/runtime`
    /// when sandboxed). `STT_RUNTIME_DIR` still overrides it for tests/dev.
    static var directory: URL {
        if let custom = ProcessInfo.processInfo.environment["STT_RUNTIME_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("STTBar/runtime", isDirectory: true)
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

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
