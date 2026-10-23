import Foundation
import Observation

/// Removing and reordering the songs of one playlist, from its page.
///
/// The page shows the change at once (`shown(_:)`) and the server call
/// follows; if it fails, the page goes back to how it was and `error` says
/// why. One change at a time.
///
/// The Subsonic API changes a playlist's songs by position: it removes songs at
/// given positions and appends songs at the end, in one request
/// (`PlaylistSongEdit`). Positions are only right if the playlist hasn't
/// changed elsewhere since the page loaded, so each change first reads the
/// playlist again; if it differs, nothing is sent and the page reloads.
@MainActor
@Observable
public final class PlaylistSongEditor {
    public struct Server: Sendable {
        public var playlist: @Sendable (_ id: String) async throws(SubsonicError) -> Playlist
        public var edit: @Sendable (_ id: String, _ edit: PlaylistSongEdit) async throws(SubsonicError) -> Void

        public init(
            playlist: @escaping @Sendable (_ id: String) async throws(SubsonicError) -> Playlist,
            edit: @escaping @Sendable (_ id: String, _ edit: PlaylistSongEdit) async throws(SubsonicError) -> Void
        ) {
            self.playlist = playlist
            self.edit = edit
        }
    }

    public private(set) var isSaving = false
    public private(set) var error: String?

    /// The songs while a change is on its way, before the page reloads.
    private var pending: [Song]?
    @ObservationIgnored private let playlistID: String
    @ObservationIgnored private let server: Server

    public init(playlistID: String, server: Server) {
        self.playlistID = playlistID
        self.server = server
    }

    /// What the page shows: the change being saved, or the songs as loaded.
    public func shown(_ loaded: [Song]) -> [Song] {
        pending ?? loaded
    }

    /// Removes the songs at `offsets` from the playlist (not from the library).
    /// `reload` loads the page's playlist again; it runs after a change that
    /// worked, or when the playlist changed elsewhere, before the page stops
    /// showing the change, so it never flashes back to the old order.
    @discardableResult
    public func remove(
        atOffsets offsets: IndexSet, from songs: [Song], reload: @MainActor () async -> Void
    ) async -> Bool {
        let after = songs.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        return await save(from: songs, to: after, reload: reload)
    }

    /// Moves songs within the playlist, as a list's drag reports it:
    /// `destination` is a position in the list before the move.
    @discardableResult
    public func move(
        fromOffsets offsets: IndexSet, toOffset destination: Int, in songs: [Song], reload: @MainActor () async -> Void
    ) async -> Bool {
        let moving = offsets.sorted().filter(songs.indices.contains).map { songs[$0] }
        var after = songs.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertAt = destination - offsets.filter { $0 < destination }.count
        after.insert(contentsOf: moving, at: min(max(insertAt, 0), after.count))
        return await save(from: songs, to: after, reload: reload)
    }

    public func dismissError() {
        error = nil
    }

    private func save(from before: [Song], to after: [Song], reload: @MainActor () async -> Void) async -> Bool {
        guard !isSaving else { return false }
        let edit = PlaylistSongEdit(from: before.map(\.id), to: after.map(\.id))
        guard !edit.isEmpty else { return false }
        isSaving = true
        pending = after
        error = nil
        defer {
            isSaving = false
            pending = nil
        }
        do throws(SubsonicError) {
            let current = try await server.playlist(playlistID)
            guard current.songs.map(\.id) == before.map(\.id) else {
                pending = nil
                await reload()
                error = "This playlist changed somewhere else, so it was reloaded. Try again."
                return false
            }
            try await server.edit(playlistID, edit)
            await reload()
            return true
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
            return false
        }
    }
}

/// One change to a playlist's songs in the API's terms: songs removed by
/// position, then songs appended. Removals alone stay removals; any other
/// change (a move) removes everything from the first difference on and
/// appends it again in the new order, the fewest songs the API allows.
public struct PlaylistSongEdit: Equatable, Sendable {
    /// 0-based positions in the playlist before the change.
    public var removingIndexes: [Int]
    public var addingSongIDs: [String]

    public init(removingIndexes: [Int], addingSongIDs: [String]) {
        self.removingIndexes = removingIndexes
        self.addingSongIDs = addingSongIDs
    }

    public init(from before: [String], to after: [String]) {
        if let removed = Self.removals(from: before, to: after) {
            self.init(removingIndexes: removed, addingSongIDs: [])
            return
        }
        let start = zip(before, after).prefix { $0 == $1 }.count
        self.init(removingIndexes: Array(start..<before.count), addingSongIDs: Array(after[start...]))
    }

    public var isEmpty: Bool { removingIndexes.isEmpty && addingSongIDs.isEmpty }

    /// The positions removed, if `after` is `before` with some songs taken out
    /// and nothing else changed.
    private static func removals(from before: [String], to after: [String]) -> [Int]? {
        guard after.count < before.count else { return nil }
        var removed: [Int] = []
        var next = after.startIndex
        for (index, id) in before.enumerated() {
            if next < after.endIndex, after[next] == id {
                next += 1
            } else {
                removed.append(index)
            }
        }
        return next == after.endIndex ? removed : nil
    }
}
