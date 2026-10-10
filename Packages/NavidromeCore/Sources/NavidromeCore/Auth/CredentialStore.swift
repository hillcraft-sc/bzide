import Foundation
import Synchronization

/// Where the server login is kept. The app uses `KeychainCredentialStore`;
/// tests and SwiftUI previews use `InMemoryCredentialStore`.
public protocol CredentialStore: Sendable {
    /// `nil` when nothing has been saved yet.
    func load() throws(CredentialStoreError) -> ServerCredentials?
    /// Replaces whatever was saved before.
    func save(_ credentials: ServerCredentials) throws(CredentialStoreError)
    /// Succeeds even if nothing was saved.
    func delete() throws(CredentialStoreError)
}

public enum CredentialStoreError: Error, Equatable, Sendable {
    /// A Keychain call failed with this `OSStatus`.
    case keychain(OSStatus)
    /// Something was stored but couldn't be read back.
    case unreadableData
}

extension CredentialStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "Couldn't access the Keychain (error \(status))."
        case .unreadableData:
            "The saved login couldn't be read. Please sign in again."
        }
    }
}

public final class InMemoryCredentialStore: CredentialStore {
    private let stored: Mutex<ServerCredentials?>

    public init(_ credentials: ServerCredentials? = nil) {
        stored = Mutex(credentials)
    }

    public func load() -> ServerCredentials? {
        stored.withLock { $0 }
    }

    public func save(_ credentials: ServerCredentials) {
        stored.withLock { $0 = credentials }
    }

    public func delete() {
        stored.withLock { $0 = nil }
    }
}
