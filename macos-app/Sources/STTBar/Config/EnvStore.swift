import Foundation

/// Reads and writes a shell `.env` file, preserving comments, blank lines, and
/// keys the app does not manage. Only `KEY=value` / `KEY="value"` lines are
/// recognized; everything else is passed through verbatim on save.
struct EnvStore {
    let url: URL
    private var lines: [String]

    init(url: URL) throws {
        self.url = url
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        self.lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    private static func parse(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { return nil }
        let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
        guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
        else { return nil }
        var val = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if val.count >= 2, val.hasPrefix("\""), val.hasSuffix("\"") {
            val = String(val.dropFirst().dropLast())
        }
        return (key, val)
    }

    func value(_ key: String) -> String? {
        for line in lines { if let p = Self.parse(line), p.key == key { return p.value } }
        return nil
    }

    mutating func set(_ key: String, _ value: String) {
        let rendered = "\(key)=\"\(value)\""
        for i in lines.indices {
            if let p = Self.parse(lines[i]), p.key == key { lines[i] = rendered; return }
        }
        if let last = lines.last, last.isEmpty { lines.insert(rendered, at: lines.count - 1) }
        else { lines.append(rendered) }
    }

    func save() throws {
        let text = lines.joined(separator: "\n")
        let tmp = url.appendingPathExtension("tmp")
        try text.write(to: tmp, atomically: true, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}
