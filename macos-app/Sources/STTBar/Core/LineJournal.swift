import Foundation

/// Shared handling for the append-only line files (events.jsonl, metrics.jsonl,
/// sttbar.log). Reads touch only the tail of the file and appends trim it once
/// it outgrows its budget, so a long-lived install neither slows down the 2 s
/// status polling nor grows without bound on disk.
enum LineJournal {
    static let defaultTailBytes: UInt64 = 262_144      // 256 KB per read
    static let defaultMaxBytes: UInt64 = 5_242_880     // trim beyond 5 MB…
    static let defaultKeepBytes: UInt64 = 1_048_576    // …down to the last 1 MB

    /// The last `maxBytes` of the file, cut down to complete lines. Returns nil
    /// when the file does not exist or cannot be read.
    static func tail(of url: URL, maxBytes: UInt64 = defaultTailBytes) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > maxBytes ? size - maxBytes : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd() else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        if start > 0 {
            guard let newline = text.firstIndex(of: "\n") else { return "" }
            text = String(text[text.index(after: newline)...])
        }
        return text
    }

    /// Appends `text` (callers pass complete lines ending in "\n") and trims
    /// the file back to `keepBytes` once it exceeds `maxBytes`. The trim is an
    /// atomic rewrite; a concurrent append from the shell backend could lose
    /// that one line, which is acceptable for status journals.
    static func append(_ text: String, to url: URL,
                       maxBytes: UInt64 = defaultMaxBytes,
                       keepBytes: UInt64 = defaultKeepBytes) {
        var size: UInt64 = 0
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            size = (try? handle.seekToEnd()) ?? 0
            try? handle.write(contentsOf: Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        if size > maxBytes, let tail = tail(of: url, maxBytes: keepBytes) {
            try? tail.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
