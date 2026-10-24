import CryptoKit
import Foundation

/// Look Up Artists Online's sources: MusicBrainz for the artist and their
/// releases, Wikipedia (through MusicBrainz's link) for the biography.
///
/// Answers are kept on disk for `cacheLifetime` (found or not), so opening an
/// artist again asks nothing, and MusicBrainz's one-a-second limit isn't
/// spent twice on the same artist. The cache holds only public catalog data,
/// shared by every account; it's in Caches, so iOS may clear it.
public actor OnlineArtistLookup: ArtistLookup {
    public static let directoryName = "ArtistLookups"
    static let cacheLifetime: TimeInterval = 14 * 86_400

    private let musicBrainz: MusicBrainzClient
    private let wikipedia: WikipediaClient
    private let directory: URL?
    private let now: @Sendable () -> Date
    /// For this session: names already searched, so a page's two lookups search once.
    private var foundIDs: [String: String?] = [:]

    public init(
        musicBrainz: MusicBrainzClient, wikipedia: WikipediaClient, directory: URL?,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.musicBrainz = musicBrainz
        self.wikipedia = wikipedia
        self.directory = directory
        self.now = now
    }

    public func biography(for artist: ArtistReference) async throws -> ArtistBiography? {
        guard let id = try await musicBrainzID(for: artist) else { return nil }
        if let cached: ArtistBiography? = cached("biography-\(id)") { return cached }
        let links = try await musicBrainz.links(artistID: id)
        let biography = try await wikipedia.biography(links)
        store(biography, "biography-\(id)")
        return biography
    }

    public func discography(for artist: ArtistReference) async throws -> [DiscographyRelease] {
        guard let id = try await musicBrainzID(for: artist) else { return [] }
        if let cached: [DiscographyRelease] = cached("discography-\(id)") { return cached }
        let releases = try await musicBrainz.releaseGroups(artistID: id)
        store(releases, "discography-\(id)")
        return releases
    }

    public func releaseTracks(for artist: ArtistReference) async throws -> [ReleaseTracks] {
        guard let id = try await musicBrainzID(for: artist) else { return [] }
        if let cached: [ReleaseTracks] = cached("releases-\(id)") { return cached }
        let releases = try await musicBrainz.releaseTracks(artistID: id)
        store(releases, "releases-\(id)")
        return releases
    }

    public func tracklist(releaseID: String) async throws -> [String] {
        if let cached: [String] = cached("tracklist-\(releaseID)") { return cached }
        let titles = try await musicBrainz.tracklist(releaseID: releaseID)
        store(titles, "tracklist-\(releaseID)")
        return titles
    }

    /// The server's id, else the one found by name (searched once).
    private func musicBrainzID(for artist: ArtistReference) async throws -> String? {
        if let id = artist.musicBrainzID { return id }
        let key = "id-" + MusicBrainzClient.nameKey(artist.name)
        if let known = foundIDs[key] { return known }
        if let cached: String? = cached(key) {
            foundIDs[key] = cached
            return cached
        }
        let id = try await musicBrainz.artistID(named: artist.name)
        foundIDs[key] = id
        store(id, key)
        return id
    }

    // MARK: - Cache

    private struct Entry<Value: Codable>: Codable {
        let savedAt: Date
        let value: Value
    }

    /// `nil` when nothing fresh is kept (`.some(nil)` is a kept "none").
    private func cached<Value: Codable>(_ key: String) -> Value? {
        guard let file = file(key), let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data),
              now().timeIntervalSince(entry.savedAt) < Self.cacheLifetime else { return nil }
        return entry.value
    }

    private func store<Value: Codable>(_ value: Value, _ key: String) {
        guard let file = file(key), let data = try? JSONEncoder().encode(Entry(savedAt: now(), value: value)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// Hashed, so names and ids can be any text.
    private func file(_ key: String) -> URL? {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appending(path: hash + ".json")
    }
}
