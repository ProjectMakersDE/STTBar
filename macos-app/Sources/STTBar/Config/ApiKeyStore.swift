import Foundation
import Security

/// API keys for hosted Whisper and LLM endpoints (OpenRouter, OpenAI, a
/// Whisper server behind a key). Keys live in the login keychain, filed under
/// the endpoint's host, and never in `.env`: that file is copied to a backup on
/// every apply and feeds profiles and the export bundle. Filing by host means a
/// key only ever travels to the server it was entered for, even after a
/// profile switch points a URL somewhere else.
enum ApiKeyStore {
    static let service = "de.projectmakers.sttbar.api-key"

    /// Keychain account for an endpoint URL: lowercased host plus an explicit
    /// port. nil for anything that is not an http(s) URL with a host.
    static func account(for urlString: String) -> String? {
        guard let components = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        return components.port.map { "\(host):\($0)" } ?? host
    }

    static func key(for urlString: String) -> String {
        guard let account = account(for: urlString) else { return "" }
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Stores the key for the URL's host; an empty key removes it.
    static func setKey(_ key: String, for urlString: String) {
        guard let account = account(for: urlString) else { return }
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = baseQuery(account)
        guard !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "STTBar API key (\(account))"
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Adds `Authorization: Bearer <key>` when a key is set.
    static func authorize(_ request: inout URLRequest, key: String) {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        request.setValue("Bearer \(value)", forHTTPHeaderField: "Authorization")
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
