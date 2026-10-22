import Foundation
import Security

/// Stores one server login as a single Keychain item.
///
/// URL, username and password (or API key) are kept together so they can
/// never get out of sync.
public struct KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account = "server"

    /// `service` only needs changing to keep tests away from the real item.
    public init(service: String = "MusicApp.server") {
        self.service = service
    }

    public func load() throws(CredentialStoreError) -> ServerCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw .keychain(status) }
        guard let data = result as? Data, let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data) else {
            throw .unreadableData
        }
        return stored.credentials
    }

    public func save(_ credentials: ServerCredentials) throws(CredentialStoreError) {
        guard let data = try? JSONEncoder().encode(StoredCredentials(credentials)) else {
            throw .unreadableData
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Playback continues with the screen locked and needs the password to sign
            // stream URLs, so the item must stay readable while locked. "ThisDeviceOnly"
            // keeps it out of backups and off other devices.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw .keychain(updateStatus) }

        let addStatus = SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw .keychain(addStatus) }
    }

    public func delete() throws(CredentialStoreError) {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// The on-disk shape. Kept separate from `ServerCredentials` so that type never
/// becomes `Codable` and can't be written somewhere else by accident.
private struct StoredCredentials: Codable {
    let baseURL: URL
    let username: String
    let password: String
    /// Missing in items saved before API keys.
    let apiKey: String?

    init(_ credentials: ServerCredentials) {
        baseURL = credentials.baseURL
        username = credentials.username
        password = credentials.password
        apiKey = credentials.apiKey
    }

    var credentials: ServerCredentials {
        ServerCredentials(baseURL: baseURL, username: username, password: password, apiKey: apiKey)
    }
}
