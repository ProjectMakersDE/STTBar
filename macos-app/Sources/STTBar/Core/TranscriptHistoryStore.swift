import Foundation

struct TranscriptHistoryItem: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var mode: String
    var text: String
}

final class TranscriptHistoryStore {
    private let url: URL
    private let settings: AppSettings
    private let now: () -> Date
    private(set) var items: [TranscriptHistoryItem]

    init(directory: URL = InstallPaths.containerDirectory(),
         settings: AppSettings = .shared,
         now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.now = now
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("transcript-history.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([TranscriptHistoryItem].self, from: data) {
            self.items = decoded
        } else {
            self.items = []
        }
        purgeExpired()
    }

    func add(text: String, mode: SttMode) {
        purgeExpired()
        guard settings.historyEnabled, !settings.sensitiveMode else { return }
        items.insert(TranscriptHistoryItem(date: now(), mode: mode.rawValue, text: text), at: 0)
        items = Array(items.prefix(20))
        persist()
    }

    func clear() {
        items.removeAll()
        try? FileManager.default.removeItem(at: url)
    }

    /// Called at launch, on privacy changes and by the app's periodic timer.
    /// Expiry remains active even while new history entries are disabled.
    @discardableResult
    func purgeExpired() -> Bool {
        let cutoff = now().addingTimeInterval(-Double(max(1, settings.historyRetentionHours)) * 3600)
        let retained = Array(items.filter { $0.date >= cutoff }.prefix(20))
        guard retained != items else { return false }
        items = retained
        if items.isEmpty { try? FileManager.default.removeItem(at: url) }
        else { persist() }
        return true
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
