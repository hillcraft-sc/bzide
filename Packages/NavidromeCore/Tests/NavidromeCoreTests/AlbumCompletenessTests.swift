import Foundation
import Synchronization
import Testing
@testable import NavidromeCore

/// Whether the user has all of an album (Gitea #31).
struct AlbumCompletenessTests {
    private func songs(_ tracks: [Int?], disc: Int? = nil) -> [Song] {
        tracks.enumerated().map { Song(id: "so-\(disc ?? 1)-\($0.offset)", title: "Song", track: $0.element, discNumber: disc) }
    }

    @Test func gapsBetweenOwnedTracks() {
        #expect(AlbumCompleteness.gaps(in: songs([1, 2, 4, 5])) == [.init(disc: 1, track: 3)])
        // Starting late: the first tracks are missing.
        #expect(AlbumCompleteness.gaps(in: songs([3, 4])) == [.init(disc: 1, track: 1), .init(disc: 1, track: 2)])
        #expect(AlbumCompleteness.gaps(in: songs([1, 2, 3])).isEmpty)
    }

    @Test func gapsAreFoundOnEachDisc() {
        let both = songs([1, 2, 3], disc: 1) + songs([1, 3], disc: 2)
        #expect(AlbumCompleteness.gaps(in: both) == [.init(disc: 2, track: 2)])
    }

    @Test func withoutTrackNumbersGapsAreUnknown() {
        #expect(AlbumCompleteness.gaps(in: songs([1, nil, 4])).isEmpty)
        #expect(AlbumCompleteness.gaps(in: []).isEmpty)
    }

    @Test func badgeAndDetail() {
        let counted = AlbumCompleteness(owned: 9, total: 12)
        #expect(counted.badge == "9 of 12 tracks")
        #expect(counted.detail == "You have 9 of 12 tracks.")

        // Only the count, never a list of numbers: gaps can't see past the
        // last owned track (owning track 2 of 8 shows only 1 missing).
        let both = AlbumCompleteness(owned: 1, total: 8, gaps: [.init(disc: 1, track: 1)])
        #expect(both.detail == "You have 1 of 8 tracks.")

        let gapsOnly = AlbumCompleteness(owned: 8, gaps: [.init(disc: 1, track: 3), .init(disc: 1, track: 7)])
        #expect(gapsOnly.badge == "Missing tracks")
        #expect(gapsOnly.detail == "Some tracks are missing.")

        let whole = AlbumCompleteness(owned: 12, total: 12)
        #expect(!whole.isIncomplete)
        #expect(whole.badge == nil && whole.detail == nil)
    }

    @Test func theMusicBrainzPageIsTheTaggedReleaseElseASearch() throws {
        var album = Album(id: "al-1", name: "Looking Glass", artist: "Looking Glass")
        let search = try #require(MusicBrainzClient.albumPage(album))
        #expect(search.host() == "musicbrainz.org" && search.path() == "/search")
        let query = URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "query" }?.value
        #expect(query == #"release:"Looking Glass" AND artist:"Looking Glass""#)
        album.musicBrainzID = "abc-123"
        #expect(MusicBrainzClient.albumPage(album)?.absoluteString == "https://musicbrainz.org/release/abc-123")
    }

    @Test func aDeluxeEditionOwnedIsComplete() {
        #expect(!AlbumCompleteness(owned: 15, total: 12).isIncomplete)
    }

    @Test func theTaggedReleaseDecides() {
        var album = Album(id: "al-1", name: "Weathered", songCount: 9)
        album.musicBrainzID = "rel-deluxe"
        let releases = [
            ReleaseTracks(id: "rel-standard", title: "Weathered", trackCount: 11),
            ReleaseTracks(id: "rel-deluxe", title: "Weathered", trackCount: 14),
        ]
        #expect(AlbumCompleteness.expectedTracks(for: album, among: releases) == 14)
    }

    @Test func untaggedAlbumsCompareWithTheSmallestEdition() {
        let album = Album(id: "al-1", name: "Weathered (Remastered)", songCount: 11)
        let releases = [
            ReleaseTracks(id: "a", title: "Weathered", trackCount: 14),
            ReleaseTracks(id: "b", title: "Weathered", trackCount: 11),
            ReleaseTracks(id: "c", title: "Human Clay", trackCount: 12),
        ]
        let completeness = AlbumCompleteness.of(album, songs: nil, releases: releases)
        #expect(completeness.total == 11)
        #expect(!completeness.isIncomplete)
    }

    @Test func theServersSongCountStandsInWithoutSongs() {
        let album = Album(id: "al-1", name: "Weathered", songCount: 9)
        let completeness = AlbumCompleteness.of(album, songs: nil, releases: [ReleaseTracks(id: "a", title: "Weathered", trackCount: 11)])
        #expect(completeness.badge == "9 of 11 tracks")
    }

    @Test func markingIsOnByDefaultAndOlderSettingsKeepIt() throws {
        #expect(StreamingSettings().markIncompleteAlbums)
        let older = try JSONDecoder().decode(StreamingSettings.self, from: Data(#"{"wifiQuality":0,"cellularQuality":192}"#.utf8))
        #expect(older.markIncompleteAlbums)
    }

    @Test func musicBrainzReleasesCountAudioTracksOnly() throws {
        let json = #"""
        {"release-count": 2, "releases": [
          {"id": "r1", "title": "Weathered", "media": [{"format": "CD", "track-count": 11}, {"format": "DVD-Video", "track-count": 6}]},
          {"id": "r2", "title": "", "media": [{"format": "CD", "track-count": 3}]}
        ]}
        """#
        let browse = try JSONDecoder().decode(MusicBrainzClient.ReleaseBrowse.self, from: Data(json.utf8))
        #expect(browse.releases?.compactMap(\.tracks) == [ReleaseTracks(id: "r1", title: "Weathered", trackCount: 11)])
    }
}

@MainActor
struct AlbumCompletenessModelTests {
    final class Server: Sendable {
        let albumFetches = Mutex(0)
        let releaseLookups = Mutex(0)
        let albums: [String: Album]

        init(_ albums: [Album]) {
            self.albums = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        }

        var sources: AlbumCompletenessModel.Sources {
            AlbumCompletenessModel.Sources(
                album: { id async throws(SubsonicError) in
                    self.albumFetches.withLock { $0 += 1 }
                    guard let album = self.albums[id] else { throw .server(code: 70, message: "Not found") }
                    return album
                },
                releases: { _ in
                    self.releaseLookups.withLock { $0 += 1 }
                    return [ReleaseTracks(id: "r", title: "Full", trackCount: 3)]
                }
            )
        }
    }

    private let gappy = Album(id: "al-1", name: "Gappy", songCount: 2, songs: [
        Song(id: "s1", title: "One", track: 1), Song(id: "s3", title: "Three", track: 3),
    ])
    private let full = Album(id: "al-2", name: "Full", songCount: 3, songs: [
        Song(id: "t1", title: "One", track: 1), Song(id: "t2", title: "Two", track: 2), Song(id: "t3", title: "Three", track: 3),
    ])

    private func artist(_ albums: [Album]) -> Artist {
        var artist = Artist(id: "ar-1", name: "Band")
        // As getArtist lists them: without songs.
        artist.albums = albums.map { var album = $0; album.songs = []; return album }
        return artist
    }

    @Test func anArtistsAlbumsAreChecked() async {
        let server = Server([gappy, full])
        let model = AlbumCompletenessModel(sources: server.sources)
        await model.load(artist([gappy, full]), info: nil, online: false)
        #expect(model.completeness(of: "al-1")?.badge == "Missing tracks")
        #expect(model.completeness(of: "al-2")?.isIncomplete == false)
        // Offline: MusicBrainz isn't asked.
        #expect(server.releaseLookups.withLock { $0 } == 0)
    }

    @Test func onlineAddsTheFullCount() async {
        // Tracks 1 and 2 of 3: no gap, so only MusicBrainz's count shows it.
        var short = full
        short.songCount = 2
        short.songs = Array(full.songs.prefix(2))
        let server = Server([short])
        let model = AlbumCompletenessModel(sources: server.sources)
        await model.load(artist([short]), info: nil, online: true)
        #expect(model.completeness(of: "al-2")?.badge == "2 of 3 tracks")
        #expect(server.releaseLookups.withLock { $0 } == 1)
    }

    @Test func onlineMarksWaitForMusicBrainz() async {
        // MusicBrainz answers only when told to.
        let (answers, answer) = AsyncStream.makeStream(of: Void.self)
        let gate = Mutex(answers.makeAsyncIterator())
        let started = Mutex(false)
        let sources = AlbumCompletenessModel.Sources(
            album: { _ async throws(SubsonicError) in throw .server(code: 70, message: "Not used") },
            releases: { _ in
                started.withLock { $0 = true }
                var iterator = gate.withLock { $0 }
                _ = await iterator.next()
                return [ReleaseTracks(id: "r", title: "Gappy", trackCount: 5)]
            }
        )
        let model = AlbumCompletenessModel(sources: sources)
        var album = gappy
        album.artist = "Band"
        let loading = Task { await model.load(album, online: true) }
        while !started.withLock({ $0 }) { await Task.yield() }
        // No "Missing tracks" first: nothing until MusicBrainz answers.
        #expect(model.completeness(of: "al-1") == nil)
        answer.yield()
        await loading.value
        #expect(model.completeness(of: "al-1")?.badge == "2 of 5 tracks")
    }

    @Test func pagesOpenedTogetherShareOneLookup() async {
        let server = Server([gappy])
        let model = AlbumCompletenessModel(sources: server.sources)
        var album = gappy
        album.artist = "Band"
        async let one: Void = model.load(album, online: true)
        async let two: Void = model.load(artist([gappy]), info: nil, online: true)
        _ = await (one, two)
        #expect(server.releaseLookups.withLock { $0 } == 1)
    }

    @Test func albumsAreFetchedOncePerSession() async {
        let server = Server([gappy, full])
        let model = AlbumCompletenessModel(sources: server.sources)
        await model.load(artist([gappy, full]), info: nil, online: false)
        await model.load(artist([gappy, full]), info: nil, online: false)
        #expect(server.albumFetches.withLock { $0 } == 2)
    }

    @Test func anAlbumPageUsesItsOwnSongs() async {
        let server = Server([])
        let model = AlbumCompletenessModel(sources: server.sources)
        await model.load(gappy, online: false)
        #expect(model.completeness(of: "al-1")?.detail == "Some tracks are missing.")
        #expect(server.albumFetches.withLock { $0 } == 0)
    }
}
