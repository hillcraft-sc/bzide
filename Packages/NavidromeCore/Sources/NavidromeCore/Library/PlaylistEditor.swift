import Foundation
import Observation

/// Creates playlists and adds songs to them, shared by every screen that offers
/// "Add to Playlist". Only playlists the signed-in user owns can be changed, so
/// only those are offered.
///
/// Adding skips songs already in the playlist (and repeats within what's being
/// added). Long lists go to the server in chunks, because each song id is part
/// of the request URL.
@MainActor
@Observable
public final class PlaylistEditor {
    /// What's being added: songs already at hand, or an album to fetch first.
    public enum Source: Sendable, Equatable {
        case songs([Song])
        case album(id: String)
    }

    public struct Server: Sendable {
        public var playlists: @Sendable () async throws(SubsonicError) -> [Playlist]
        public var playlist: @Sendable (_ id: String) async throws(SubsonicError) -> Playlist
        public var albumSongs: @Sendable (_ albumID: String) async throws(SubsonicError) -> [Song]
        public var create: @Sendable (_ name: String, _ songIDs: [String]) async throws(SubsonicError) -> Playlist?
        public var add: @Sendable (_ playlistID: String, _ songIDs: [String]) async throws(SubsonicError) -> Void

        public init(
            playlists: @escaping @Sendable () async throws(SubsonicError) -> [Playlist],
            playlist: @escaping @Sendable (_ id: String) async throws(SubsonicError) -> Playlist,
            albumSongs: @escaping @Sendable (_ albumID: String) async throws(SubsonicError) -> [Song],
            create: @escaping @Sendable (_ name: String, _ songIDs: [String]) async throws(SubsonicError) -> Playlist?,
            add: @escaping @Sendable (_ playlistID: String, _ songIDs: [String]) async throws(SubsonicError) -> Void
        ) {
            self.playlists = playlists
            self.playlist = playlist
            self.albumSongs = albumSongs
            self.create = create
            self.add = add
        }
    }

    /// The playlists that can be added to, by name.
    public private(set) var playlists: LoadState<[Playlist]> = .loading
    public private(set) var isSaving = false
    public private(set) var error: String?
    /// What the last change did, e.g. "Added 8 songs to “Morning”."
    public private(set) var confirmation: String?

    @ObservationIgnored private let username: String
    @ObservationIgnored private let server: Server

    /// Song ids per request. Keeps the URL well under the 8 KB many servers and
    /// proxies accept.
    static let chunkSize = 100

    public init(username: String, server: Server) {
        self.username = username
        self.server = server
    }

    public func loadPlaylists() async {
        if case .failed = playlists { playlists = .loading }
        do {
            let all = try await server.playlists()
            playlists = .loaded(all.filter(isOwned).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            })
        } catch {
            if Task.isCancelled { return }
            // A list already shown stays; only a first load shows the error.
            if case .loaded = playlists { return }
            playlists = .failed(error.localizedDescription)
        }
    }

    /// Adds the songs to the end of `playlist`. Returns whether it worked.
    @discardableResult
    public func add(_ source: Source, to playlist: Playlist) async -> Bool {
        await save { () async throws(SubsonicError) -> String in
            let songs = try await self.songs(from: source)
            let existing = Set(try await self.server.playlist(playlist.id).songs.map(\.id))
            var seen = existing
            let new = songs.map(\.id).filter { seen.insert($0).inserted }
            for chunk in new.chunks(of: Self.chunkSize) {
                try await self.server.add(playlist.id, chunk)
            }
            return Self.addedMessage(added: new.count, skipped: songs.count - new.count, to: playlist.name)
        }
    }

    /// A new playlist holding the songs in order, repeats included (a queue
    /// saved as a playlist keeps its shape). Returns whether it worked.
    @discardableResult
    public func create(named name: String, with source: Source) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return await save { () async throws(SubsonicError) -> String in
            let ids = try await self.songs(from: source).map(\.id)
            let chunks = ids.chunks(of: Self.chunkSize)
            let created = try await self.server.create(name, chunks.first ?? [])
            if chunks.count > 1 {
                // The rest go to the new playlist, which needs its id.
                guard let created else { throw SubsonicError.decoding("The server didn't return the new playlist.") }
                for chunk in chunks.dropFirst() {
                    try await self.server.add(created.id, chunk)
                }
            }
            return ids.isEmpty ? "Created “\(name)”." : "Created “\(name)” with \(Self.songs(ids.count))."
        }
    }

    public func dismissError() {
        error = nil
    }

    public func dismissConfirmation() {
        confirmation = nil
    }

    // MARK: - Private

    private func isOwned(_ playlist: Playlist) -> Bool {
        // A server that doesn't say who owns it gets the benefit of the doubt;
        // it refuses the change if it's not ours.
        guard let owner = playlist.owner else { return true }
        return owner == username
    }

    private func songs(from source: Source) async throws(SubsonicError) -> [Song] {
        switch source {
        case .songs(let songs): songs
        case .album(let id): try await server.albumSongs(id)
        }
    }

    /// Runs one change at a time and reports how it went. The playlists are
    /// reloaded afterwards either way, since a chunked change can half succeed.
    private func save(_ change: () async throws(SubsonicError) -> String) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        error = nil
        confirmation = nil
        defer { isSaving = false }
        var succeeded = false
        do {
            confirmation = try await change()
            succeeded = true
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
        await loadPlaylists()
        return succeeded
    }

    static func addedMessage(added: Int, skipped: Int, to name: String) -> String {
        if added == 0 {
            return skipped == 1 ? "That song is already in “\(name)”." : "All \(skipped) songs are already in “\(name)”."
        }
        let message = "Added \(songs(added)) to “\(name)”."
        guard skipped > 0 else { return message }
        return message + (skipped == 1 ? " 1 was already there." : " \(skipped) were already there.")
    }

    static func songs(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count) songs"
    }
}

extension Array {
    /// Consecutive slices of at most `size` elements; none for an empty array.
    func chunks(of size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
