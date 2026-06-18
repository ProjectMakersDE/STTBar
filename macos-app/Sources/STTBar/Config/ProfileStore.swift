import Foundation

struct SttProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var whisperURL: String
    var whisperModel: String
    var language: String
    var transcribeTimeout: String
    var postprocessEnabled: Bool
    var postprocessURL: String
    var postprocessModel: String
    var provider: String
    var postprocessTimeout: String
    var autoRawFallback: Bool
}

struct ProfileStore {
    private let url: URL
    private(set) var activeId: String?
    private(set) var profiles: [SttProfile]

    private struct Persisted: Codable {
        var activeId: String?
        var profiles: [SttProfile]
    }

    init(directory: URL) {
        self.url = directory.appendingPathComponent("profiles.json")
        if let data = try? Data(contentsOf: url),
           let persisted = try? JSONDecoder().decode(Persisted.self, from: data) {
            self.activeId = persisted.activeId
            self.profiles = persisted.profiles
        } else {
            self.activeId = nil
            self.profiles = []
        }
    }

    mutating func upsert(_ profile: SttProfile, makeActive: Bool) throws {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        if makeActive { activeId = profile.id }
        try persist()
    }

    mutating func remove(_ id: String) throws {
        profiles.removeAll { $0.id == id }
        if activeId == id { activeId = profiles.first?.id }
        try persist()
    }

    mutating func setActive(_ id: String) throws {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeId = id
        try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(Persisted(activeId: activeId, profiles: profiles))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
