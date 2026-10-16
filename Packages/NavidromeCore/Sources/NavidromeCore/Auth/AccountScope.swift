import CryptoKit
import Foundation

/// Keeps one account's data from leaking into another's.
///
/// Downloads, the saved queue, unsent scrobbles, play history, cached cover
/// art, the profile (its settings and pictures), the radio stations saved
/// on this iPhone and what's remembered about saved stations all belong to the server
/// and user they came from. Signing out leaves them in place, so signing back
/// in to the same account keeps everything. Signing in to a different server
/// or user deletes them first.
///
/// The owning account is remembered as a fingerprint (a hash of server address
/// and username), so neither is stored outside the Keychain.
public struct AccountScope {
    private let defaults: UserDefaults
    private let dataLocations: [URL]

    static let fingerprintKey = "accountFingerprint"

    public init(defaults: UserDefaults = .standard, dataLocations: [URL]) {
        self.defaults = defaults
        self.dataLocations = dataLocations
    }

    /// Every file and folder holding account data, in their standard places.
    public static func standardDataLocations() throws -> [URL] {
        let fileManager = FileManager.default
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return [
            support.appending(path: FileQueueStore.fileName),
            support.appending(path: FileScrobbleStore.fileName),
            support.appending(path: PlayHistory.fileName),
            support.appending(path: DownloadManager.directoryName),
            caches.appending(path: CoverArtStore.directoryName),
            support.appending(path: ProfileModel.fileName),
            support.appending(path: ProfileModel.picturesDirectoryName),
            caches.appending(path: ProfileModel.cacheDirectoryName),
            support.appending(path: PhoneStationStore.fileName),
            support.appending(path: StationDetailsStore.fileName),
            support.appending(path: StationDetailsStore.oldLogosFileName),
            support.appending(path: DialLog.fileName),
        ]
    }

    /// Call before any account data is loaded. Deletes the data on the device if
    /// it belongs to a different account, then records this one as the owner.
    /// Returns whether anything was deleted.
    ///
    /// With no owner recorded (data from before this check existed), the data is
    /// assumed to be this account's and kept.
    @discardableResult
    public func prepare(for credentials: ServerCredentials) -> Bool {
        let fingerprint = Self.fingerprint(of: credentials)
        defer { defaults.set(fingerprint, forKey: Self.fingerprintKey) }
        guard let owner = defaults.string(forKey: Self.fingerprintKey), owner != fingerprint else { return false }
        for location in dataLocations {
            try? FileManager.default.removeItem(at: location)
        }
        return true
    }

    /// The same server written differently (`HTTPS://Music.example.com/`) is the
    /// same account; the username is compared exactly.
    static func fingerprint(of credentials: ServerCredentials) -> String {
        var server = credentials.baseURL.absoluteString
        if var components = URLComponents(url: credentials.baseURL, resolvingAgainstBaseURL: false) {
            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            while components.path.hasSuffix("/") { components.path.removeLast() }
            server = components.string ?? server
        }
        let digest = SHA256.hash(data: Data("\(server)\n\(credentials.username)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
