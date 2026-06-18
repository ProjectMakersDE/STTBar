import Foundation

struct VersionInfo {
    let appCommit: String
    let scriptCommit: String
    let installedAt: String

    static func load(installDir: URL) -> VersionInfo {
        let appCommit = Bundle.main.object(forInfoDictionaryKey: "STTGitCommit") as? String
            ?? readBundleResource("version.txt")["commit"]
            ?? "unknown"
        let scriptValues = readKeyValueFile(installDir.appendingPathComponent("installed-version.txt"))
        return VersionInfo(appCommit: appCommit,
                           scriptCommit: scriptValues["commit"] ?? "unknown",
                           installedAt: scriptValues["installed_at"] ?? "unknown")
    }

    private static func readBundleResource(_ name: String) -> [String: String] {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name) else { return [:] }
        return readKeyValueFile(url)
    }

    private static func readKeyValueFile(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            result[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return result
    }
}
