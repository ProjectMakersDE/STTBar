import Foundation

struct TranscriptHistoryItem: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var mode: String
    var text: String
}

final class TranscriptHistoryStore {
    private let url: URL
    private(set) var items: [TranscriptHistoryItem]

    init() {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/STTBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("transcript-history.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([TranscriptHistoryItem].self, from: data) {
            self.items = decoded
        } else {
            self.items = []
        }
    }

    func add(text: String, mode: SttMode) {
        guard AppSettings.shared.historyEnabled, !AppSettings.shared.sensitiveMode else { return }
        items.insert(TranscriptHistoryItem(mode: mode.rawValue, text: text), at: 0)
        prune()
        persist()
    }

    func clear() {
        items.removeAll()
        try? FileManager.default.removeItem(at: url)
    }

    private func prune() {
        let retention = max(1, AppSettings.shared.historyRetentionHours)
        let cutoff = Date().addingTimeInterval(TimeInterval(-retention * 3600))
        items = items.filter { $0.date >= cutoff }.prefix(20).map { $0 }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
