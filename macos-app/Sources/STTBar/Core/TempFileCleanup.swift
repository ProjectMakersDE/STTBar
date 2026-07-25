import Foundation

/// Deletes the app's disposable scratch files.
///
/// Deliberately an explicit allowlist of file names: no directory removal, no
/// glob. Even if a path ever resolves wrong, this cannot take out `.env`, the
/// prompts, or the transcript history — they are simply not on the list.
enum TempFileCleanup {
    static let runtimeFileNames = ["recording.wav", "events.jsonl", "metrics.jsonl",
                                   "status.json", "phase", "last-transcript.txt"]
    static let logFileNames = ["sttbar.log"]

    struct Result: Equatable {
        var removedFiles: Int
        var freedBytes: Int64
    }

    static func removableURLs(runtime: URL, logs: URL) -> [URL] {
        runtimeFileNames.map { runtime.appendingPathComponent($0) }
            + logFileNames.map { logs.appendingPathComponent($0) }
    }

    /// A missing file is not an error and is not counted. Directories are
    /// skipped even when named like a scratch file.
    @discardableResult
    static func run(runtime: URL, logs: URL) -> Result {
        let fm = FileManager.default
        var result = Result(removedFiles: 0, freedBytes: 0)
        for url in removableURLs(runtime: runtime, logs: logs) {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            do { try fm.removeItem(at: url) } catch { continue }
            result.removedFiles += 1
            result.freedBytes += size
        }
        return result
    }
}
