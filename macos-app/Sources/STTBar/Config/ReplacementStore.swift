import Foundation

struct ReplacementEntry: Identifiable, Equatable, Codable {
    var id: String = UUID().uuidString
    var enabled: Bool = true
    var from: String
    var to: String
    var category: String = "Allgemein"
    var comment: String = ""
}

struct ReplacementStore {
    let url: URL
    private(set) var entries: [ReplacementEntry]

    init(directory: URL) {
        let configured = (try? EnvStore(url: directory.appendingPathComponent(".env")).value("STT_REPLACEMENTS_FILE")) ?? ""
        if !configured.isEmpty {
            self.url = URL(fileURLWithPath: configured)
        } else {
            self.url = directory.appendingPathComponent("stt-replacements.tsv")
        }
        self.entries = Self.load(from: url)
    }

    mutating func update(_ entries: [ReplacementEntry]) throws {
        self.entries = entries
        try persist()
    }

    mutating func add() throws {
        entries.append(ReplacementEntry(from: "", to: "", category: "Allgemein", comment: ""))
        try persist()
    }

    mutating func remove(_ id: String) throws {
        entries.removeAll { $0.id == id }
        try persist()
    }

    func preview(_ input: String) -> String {
        var output = input
        for entry in entries where entry.enabled && !entry.from.isEmpty {
            output = output.replacingOccurrences(of: entry.from, with: entry.to, options: [.caseInsensitive, .diacriticInsensitive])
        }
        return output
    }

    func persist() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let backup = url.deletingPathExtension()
            .appendingPathExtension("backup-\(Int(Date().timeIntervalSince1970)).tsv")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        let lines = entries.map { entry in
            [
                entry.enabled ? "1" : "0",
                sanitize(entry.from),
                sanitize(entry.to),
                sanitize(entry.category),
                sanitize(entry.comment),
            ].joined(separator: "\t")
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func load(from url: URL) -> [ReplacementEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                return nil
            }
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 3, ["0", "1", "true", "false", "on", "off"].contains(parts[0].lowercased()) {
                return ReplacementEntry(enabled: ["1", "true", "on"].contains(parts[0].lowercased()),
                                        from: parts[1],
                                        to: parts[2],
                                        category: parts.count > 3 ? parts[3] : "Allgemein",
                                        comment: parts.count > 4 ? parts[4] : "")
            }
            if parts.count >= 2 {
                return ReplacementEntry(enabled: true, from: parts[0], to: parts[1], category: "Allgemein", comment: "")
            }
            return nil
        }
    }

    private func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
