import Foundation

struct PromptVersion: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var note: String
    var body: String
}

struct Prompt: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var body: String
    var versions: [PromptVersion]

    init(id: String, title: String, body: String, versions: [PromptVersion] = []) {
        self.id = id
        self.title = title
        self.body = body
        self.versions = versions
    }

    private enum CodingKeys: String, CodingKey { case id, title, body, versions }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        versions = (try? container.decode([PromptVersion].self, forKey: .versions)) ?? []
    }
}

/// Persists named prompts to `prompts.json` and mirrors the active prompt body
/// to `active-prompt.txt`, which `.env`'s STT_POSTPROCESS_PROMPT_FILE points at.
struct PromptStore {
    private let directory: URL
    private let jsonURL: URL
    let activeFileURL: URL
    private(set) var prompts: [Prompt]
    private(set) var activeId: String

    var activePrompt: Prompt? { prompts.first { $0.id == activeId } }

    private struct Persisted: Codable { var activeId: String; var prompts: [Prompt] }

    init(directory: URL, defaultBody: String) throws {
        self.directory = directory
        self.jsonURL = directory.appendingPathComponent("prompts.json")
        self.activeFileURL = directory.appendingPathComponent("active-prompt.txt")
        if let data = try? Data(contentsOf: jsonURL),
           let p = try? JSONDecoder().decode(Persisted.self, from: data), !p.prompts.isEmpty {
            self.prompts = p.prompts
            self.activeId = p.prompts.contains { $0.id == p.activeId } ? p.activeId : p.prompts[0].id
        } else {
            let seed = Prompt(id: UUID().uuidString, title: "Agent-Standard (DE)", body: defaultBody)
            self.prompts = [seed]
            self.activeId = seed.id
        }
        try persist()
    }

    @discardableResult
    mutating func add(title: String, body: String) throws -> String {
        let p = Prompt(id: UUID().uuidString, title: title, body: body)
        prompts.append(p); try persist(); return p.id
    }

    mutating func update(_ id: String, title: String, body: String, note: String = "") throws {
        guard let i = prompts.firstIndex(where: { $0.id == id }) else { return }
        if prompts[i].body != body {
            let versionNote = note.isEmpty ? "Vorherige Version" : note
            prompts[i].versions.insert(PromptVersion(note: versionNote, body: prompts[i].body), at: 0)
            prompts[i].versions = Array(prompts[i].versions.prefix(20))
        }
        prompts[i].title = title; prompts[i].body = body; try persist()
    }

    mutating func remove(_ id: String) throws {
        guard prompts.count > 1 else { return }
        prompts.removeAll { $0.id == id }
        if activeId == id { activeId = prompts[0].id }
        try persist()
    }

    mutating func setActive(_ id: String) throws {
        guard prompts.contains(where: { $0.id == id }) else { return }
        activeId = id; try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(Persisted(activeId: activeId, prompts: prompts))
        try data.write(to: jsonURL, options: .atomic)
        try (activePrompt?.body ?? "").write(to: activeFileURL, atomically: true, encoding: .utf8)
    }
}
