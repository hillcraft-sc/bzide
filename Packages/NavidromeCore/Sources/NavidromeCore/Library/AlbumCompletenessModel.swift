import Foundation
import Observation

/// Works out `AlbumCompleteness` for the albums on an artist page or one album
/// page, after the page has loaded, so it never holds it up. Shared, and kept
/// for the session: going back to an artist doesn't fetch their albums again.
///
/// The gaps need each album's songs: on an artist page they're fetched a few
/// albums at a time. The full counts come from MusicBrainz, only while Look
/// Up Artists Online is on; then nothing is shown until MusicBrainz has
/// answered (or failed), so a mark appears once, with the count, rather than
/// "Missing tracks" changing to "9 of 12 tracks" seconds later. MusicBrainz's
/// one-request-a-second limit makes a big artist's first lookup take a while.
@MainActor
@Observable
public final class AlbumCompletenessModel {
    public struct Sources: Sendable {
        public var album: @Sendable (_ id: String) async throws(SubsonicError) -> Album
        public var releases: @Sendable (_ artist: ArtistReference) async throws -> [ReleaseTracks]
        public var tracklist: @Sendable (_ releaseID: String) async throws -> [ReleaseTrack]

        public init(
            album: @escaping @Sendable (_ id: String) async throws(SubsonicError) -> Album,
            releases: @escaping @Sendable (_ artist: ArtistReference) async throws -> [ReleaseTracks],
            tracklist: @escaping @Sendable (_ releaseID: String) async throws -> [ReleaseTrack] = { _ in [] }
        ) {
            self.album = album
            self.releases = releases
            self.tracklist = tracklist
        }
    }

    /// Albums fetched at once on an artist page.
    static let parallelFetches = 4

    private var results: [String: AlbumCompleteness] = [:]
    /// Albums' missing tracks, for their pages (Gitea #30).
    private var missing: [String: MissingTracks] = [:]
    /// Songs fetched this session, with the song count they were fetched at;
    /// a different count (songs added or removed) fetches again.
    @ObservationIgnored private var songs: [String: (count: Int?, songs: [Song])] = [:]
    @ObservationIgnored private var releases: [String: [ReleaseTracks]] = [:]
    /// Lookups on their way, so an artist page and an album page opened
    /// meanwhile wait for the same one rather than queueing a second.
    @ObservationIgnored private var lookups: [String: Task<[ReleaseTracks]?, Never>] = [:]
    @ObservationIgnored private let sources: Sources

    public init(sources: Sources) {
        self.sources = sources
    }

    /// `nil` until worked out.
    public func completeness(of albumID: String) -> AlbumCompleteness? {
        results[albumID]
    }

    /// An artist page: each of their albums. Their songs are read while
    /// MusicBrainz is asked; with Look Up Artists Online off, each album's mark
    /// shows as soon as its songs arrive, else all of them once MusicBrainz
    /// has answered.
    public func load(_ artist: Artist, info: ArtistInfo?, online: Bool) async {
        let reference = ArtistReference(name: artist.name, musicBrainzID: artist.musicBrainzID ?? info?.musicBrainzID)
        async let lookedUp: [ReleaseTracks] = online ? releases(of: reference) : []
        if !online {
            for album in artist.albums { results[album.id] = .of(album, songs: cachedSongs(album), releases: []) }
        }
        let missing = artist.albums.filter { cachedSongs($0) == nil }
        await withTaskGroup(of: (Album, [Song]?).self) { group in
            var next = missing.makeIterator()
            func addNext() {
                guard let album = next.next() else { return }
                group.addTask { [sources] in (album, try? await sources.album(album.id).songs) }
            }
            for _ in 0..<Self.parallelFetches { addNext() }
            for await (album, fetched) in group {
                if let fetched {
                    songs[album.id] = (album.songCount, fetched)
                    if !online { results[album.id] = .of(album, songs: fetched, releases: []) }
                }
                addNext()
            }
        }
        guard online else { return }
        let known = await lookedUp
        for album in artist.albums {
            results[album.id] = .of(album, songs: cachedSongs(album), releases: known)
        }
    }

    /// An album page, with its songs already loaded.
    public func load(_ album: Album, online: Bool) async {
        songs[album.id] = (album.songCount, album.songs)
        guard online, let artist = album.artist, !artist.isEmpty, !album.details.isCompilation else {
            results[album.id] = .of(album, songs: album.songs, releases: [])
            missing[album.id] = nil
            return
        }
        let known = await releases(of: ArtistReference(name: artist, musicBrainzID: nil))
        let result = AlbumCompleteness.of(album, songs: album.songs, releases: known)
        results[album.id] = result
        if result.isIncomplete {
            _ = await missingSongs(of: album)
        } else {
            missing[album.id] = nil
        }
    }

    /// The album's tracks the user doesn't have, by title, from its release on
    /// MusicBrainz, with that release; `nil` when the release or its
    /// tracklist can't be had. Kept for `missingTracks(of:)`.
    public func missingSongs(of album: Album) async -> MissingTracks? {
        guard let artist = album.artist, !artist.isEmpty else { return nil }
        let known = await releases(of: ArtistReference(name: artist, musicBrainzID: nil))
        guard let release = AlbumCompleteness.release(for: album, among: known),
              let tracklist = try? await sources.tracklist(release.id), !tracklist.isEmpty else { return nil }
        let found = MissingTracks(
            tracks: AlbumCompleteness.missingTracks(tracklist, owned: album.songs), release: release,
            isMultiDisc: Set(tracklist.map(\.disc)).count > 1
        )
        missing[album.id] = found
        return found
    }

    /// The album page's Missing Tracks (Gitea #30), once `load(_:online:)`
    /// has found them: only for an incomplete album, with Look Up Artists Online on.
    public func missingTracks(of albumID: String) -> MissingTracks? {
        missing[albumID]
    }

    private func cachedSongs(_ album: Album) -> [Song]? {
        guard let cached = songs[album.id], cached.count == album.songCount else { return nil }
        return cached.songs
    }

    /// A failed lookup gives none (gaps still show) and is tried again next time.
    private func releases(of artist: ArtistReference) async -> [ReleaseTracks] {
        let key = artist.musicBrainzID ?? MusicBrainzClient.nameKey(artist.name)
        if let known = releases[key] { return known }
        guard artist.musicBrainzID != OnlineArtistModel.variousArtistsID else { return [] }
        let lookup = lookups[key] ?? Task { [sources] in try? await sources.releases(artist) }
        lookups[key] = lookup
        let found = await lookup.value
        lookups[key] = nil
        if let found { releases[key] = found }
        return found ?? []
    }
}
