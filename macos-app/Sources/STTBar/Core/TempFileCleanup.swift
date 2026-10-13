import Foundation

/// Deletes the app's disposable scratch files.
///
/// Deliberately an allowlist of file names and UUID recording names, with no
/// directory removal. Even if a path ever resolves wrong, this cannot take out `.env`, the
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
            + orphanedRecordingURLs(runtime: runtime)
    }

    private static func orphanedRecordingURLs(runtime: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: runtime,
                     includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])) ?? []
        return files.filter {
            let name = $0.lastPathComponent
            guard name.hasPrefix("recording-"), name.hasSuffix(".wav") else { return false }
            let identifier = String(name.dropFirst("recording-".count).dropLast(".wav".count))
            return UUID(uuidString: identifier) != nil
        }
    }

    /// Called before the native recorder is created, so files abandoned by a
    /// terminated run cannot persist indefinitely. The native app also migrates
    /// its old fixed filename in the default container. With a runtime override,
    /// leave that filename alone because a shell recorder may own it.
    @discardableResult
    static func removeOrphanedRecordings(runtime: URL, includeLegacy: Bool = false) -> Result {
        remove(orphanedRecordingURLs(runtime: runtime)
            + (includeLegacy ? [runtime.appendingPathComponent("recording.wav")] : []))
    }

    /// A missing file is not an error and is not counted. Directories are
    /// skipped even when named like a scratch file.
    @discardableResult
    static func run(runtime: URL, logs: URL) -> Result {
        remove(removableURLs(runtime: runtime, logs: logs))
    }

    private static func remove(_ urls: [URL]) -> Result {
        let fm = FileManager.default
        var result = Result(removedFiles: 0, freedBytes: 0)
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let size = Int64(values.fileSize ?? 0)
            do { try fm.removeItem(at: url) } catch { continue }
            result.removedFiles += 1
            result.freedBytes += size
        }
        return result
    }
}
