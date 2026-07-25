import AppKit
import Foundation

/// The three on-disk areas STTBar owns. Paths come from the existing
/// resolvers; this enum only groups and labels them for the UI.
enum DataLocation: String, CaseIterable, Identifiable {
    case config, runtime, logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .config: return L("Konfiguration", "Configuration")
        case .runtime: return L("Laufzeit (temporär)", "Runtime (temporary)")
        case .logs: return L("Logs", "Logs")
        }
    }

    var detail: String {
        switch self {
        case .config: return L("Einstellungen, Prompts, Wörterbuch, Verlauf",
                               "Settings, prompts, vocabulary, history")
        case .runtime: return L("Aufnahme, Events, Metriken, Status",
                                "Recording, events, metrics, status")
        case .logs: return L("Protokolldatei sttbar.log", "Log file sttbar.log")
        }
    }

    var url: URL {
        switch self {
        case .config: return InstallPaths.resolve()
        case .runtime: return RuntimePaths.directory
        case .logs: return AppLogger.logURL.deletingLastPathComponent()
        }
    }

    /// `runtime` sits inside `config`. Counting it in both would report the
    /// same bytes twice and make the three numbers add up to nonsense.
    var excludedFromSize: URL? { self == .config ? RuntimePaths.directory : nil }

    var byteCount: Int64 { DirectorySize.bytes(of: url, excluding: excludedFromSize) }

    /// Opens the folder itself in Finder. `open` rather than
    /// `activateFileViewerSelecting`: the point is to look *inside* the folder,
    /// not to select it in its parent.
    func reveal() {
        let url = self.url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

enum DirectorySize {
    /// Recursive sum of regular-file sizes. A missing directory is 0, not an
    /// error. Hidden files are counted — `.env` is the whole point of the
    /// config folder.
    static func bytes(of directory: URL, excluding excluded: URL? = nil) -> Int64 {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: directory,
                                         includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        else { return 0 }
        let skip = excluded?.standardizedFileURL.path
        var total: Int64 = 0
        for case let url as URL in walker {
            if let skip {
                let path = url.standardizedFileURL.path
                if path == skip || path.hasPrefix(skip + "/") { continue }
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }
}
