import Foundation

/// Cover art on disk, as the server sent it (image bytes, not decoded).
///
/// Two places:
/// - the cache, in Caches: every image fetched, one file per size. iOS may
///   clear it when space runs low; it refills from the server.
/// - pinned, next to the downloads: one image per cover kept for downloaded
///   albums and playlists, so they have artwork offline. Removed with them.
///
/// Plain file reads and writes; call from off the main thread.
public struct CoverArtStore: Sendable {
    let cacheDirectory: URL
    let pinnedDirectory: URL

    public init(cacheDirectory: URL, pinnedDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        self.pinnedDirectory = pinnedDirectory
    }

    /// `Caches/CoverArt` and `Downloads/CoverArt` (inside the downloads folder,
    /// so it shares its backup exclusion).
    public static func standard(downloadsDirectory: URL) throws -> CoverArtStore {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return CoverArtStore(
            cacheDirectory: caches.appending(path: "CoverArt"),
            pinnedDirectory: downloadsDirectory.appending(path: "CoverArt")
        )
    }

    /// The image at this size, or the pinned one (it serves every size).
    public func image(id: String, pixels: Int) -> Data? {
        read(cacheFile(id: id, pixels: pixels)) ?? read(pinnedFile(id: id))
    }

    /// Any copy of this cover: pinned, else the largest cached size. For when
    /// the server can't be reached; a wrong size beats no artwork.
    public func anyImage(id: String) -> Data? {
        if let pinned = read(pinnedFile(id: id)) { return pinned }
        let prefix = "\(Self.fileName(for: id))@"
        let sizes = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path(percentEncoded: false))) ?? []
        let largest = sizes
            .filter { $0.hasPrefix(prefix) }
            .max { Int($0.dropFirst(prefix.count)) ?? 0 < Int($1.dropFirst(prefix.count)) ?? 0 }
        return largest.flatMap { read(cacheDirectory.appending(path: $0)) }
    }

    public func save(_ data: Data, id: String, pixels: Int) {
        write(data, to: cacheFile(id: id, pixels: pixels), in: cacheDirectory)
    }

    public func pin(_ data: Data, id: String) {
        write(data, to: pinnedFile(id: id), in: pinnedDirectory)
    }

    public func unpin(id: String) {
        try? FileManager.default.removeItem(at: pinnedFile(id: id))
    }

    public func pinnedIDs() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: pinnedDirectory.path(percentEncoded: false))) ?? []
        return Set(names.compactMap { $0.removingPercentEncoding })
    }

    // MARK: - Files

    private func cacheFile(id: String, pixels: Int) -> URL {
        cacheDirectory.appending(path: "\(Self.fileName(for: id))@\(pixels)")
    }

    private func pinnedFile(id: String) -> URL {
        pinnedDirectory.appending(path: Self.fileName(for: id))
    }

    /// Ids come from the server; anything outside a safe set is percent-encoded
    /// so an id can never name a path outside the folder.
    static func fileName(for id: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? "invalid"
    }

    private func read(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    private func write(_ data: Data, to url: URL, in directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// Keeps cover art on the device for downloaded albums and playlists.
@MainActor
public protocol ArtworkPinning: AnyObject {
    /// Pins any of these covers not yet pinned (fetching them), and unpins any
    /// pinned cover not in the set.
    func keepOffline(coverArtIDs: Set<String>)
}
