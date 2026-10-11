import Foundation
import Testing
@testable import NavidromeCore

struct LibraryDecodingTests {
    @Test func artistsKeepServerSectionsAndOrder() async throws {
        let sections = try await TestServer.client(FakeTransport(fixture: "getArtists")).artists()
        #expect(sections.map(\.name) == ["A", "#"])
        #expect(sections[0].artists.map(\.id) == ["ar-1", "ar-2"])
        #expect(sections[0].artists[0] == Artist(id: "ar-1", name: "Aurora Lines", albumCount: 2, coverArtID: "ar-ar-1", isStarred: true, userRating: 4))
        #expect(sections[0].artists[1].isStarred == false)
        // Out of range: treated as unrated, not an error.
        #expect(sections[0].artists[1].userRating == nil)
    }

    @Test func artistIncludesAlbums() async throws {
        let artist = try await TestServer.client(FakeTransport(fixture: "getArtist")).artist(id: "ar-1")
        #expect(artist.name == "Aurora Lines")
        #expect(artist.albums.map(\.id) == ["al-1", "al-2"])
        #expect(artist.albums[1].coverArtID == nil)
    }

    @Test func albumIncludesSongsWithAllFields() async throws {
        let album = try await TestServer.client(FakeTransport(fixture: "getAlbum")).album(id: "al-1")
        #expect(album.name == "First Light")
        #expect(album.isStarred)
        #expect(album.userRating == 3)
        #expect(album.songs.count == 3)
        #expect(album.songs[0] == Song(
            id: "so-1", title: "Dawn", album: "First Light", albumID: "al-1",
            artist: "Aurora Lines", artistID: "ar-1", track: 1, discNumber: 1, year: 2019,
            genre: "Ambient", coverArtID: "mf-so-1", duration: 201, bitRate: 900,
            suffix: "flac", contentType: "audio/flac", isStarred: false, userRating: 5
        ))
        #expect(album.songs[1].isStarred)
        #expect(album.songs[1].userRating == nil)
        // Subsonic sends 0 for "unrated".
        #expect(album.songs[2].userRating == nil)
    }

    @Test func messyAlbumKeepsEverythingUsable() async throws {
        let album = try await TestServer.client(FakeTransport(fixture: "getAlbum-messy")).album(id: "17")
        #expect(album.id == "17")
        #expect(album.name == "Untitled Session")
        #expect(album.songCount == 4)
        #expect(album.year == nil)
        // Items with no usable id are dropped; everything else survives.
        #expect(album.songs.map(\.id) == ["so-10", "so-11"])

        let messy = album.songs[0]
        #expect(messy.track == 2)
        #expect(messy.duration == 187)
        #expect(messy.bitRate == 320)
        #expect(messy.discNumber == nil)
        #expect(messy.artist == nil)
        #expect(album.songs[1].title == "")
    }

    @Test func albumListDecodes() async throws {
        let albums = try await TestServer.client(FakeTransport(fixture: "getAlbumList2")).albumList(.newest)
        #expect(albums.map(\.id) == ["al-2", "al-1"])
    }

    @Test func emptyAlbumListIsEmptyNotAnError() async throws {
        let albums = try await TestServer.client(FakeTransport(fixture: "getAlbumList2-empty")).albumList(.starred)
        #expect(albums.isEmpty)
    }

    @Test func playlistsToleratesStringTypedFields() async throws {
        let playlists = try await TestServer.client(FakeTransport(fixture: "getPlaylists")).playlists()
        #expect(playlists.map(\.id) == ["pl-1", "pl-2"])
        #expect(playlists[0].isPublic == false)
        #expect(playlists[1].isPublic == true)
        #expect(playlists[1].songCount == 40)
    }

    @Test func playlistIncludesEntries() async throws {
        let playlist = try await TestServer.client(FakeTransport(fixture: "getPlaylist")).playlist(id: "pl-1")
        #expect(playlist.songs.map(\.id) == ["so-1", "so-2"])
    }

    @Test func searchAcceptsSingleObjectWhereListExpected() async throws {
        let result = try await TestServer.client(FakeTransport(fixture: "search3")).search("aurora")
        #expect(result.artists.map(\.id) == ["ar-1"])
        #expect(result.albums.map(\.id) == ["al-1"])
        #expect(result.songs.map(\.id) == ["so-1", "so-3"])
    }

    @Test func searchWithNoMatchesIsEmpty() async throws {
        let result = try await TestServer.client(FakeTransport(fixture: "search3-empty")).search("zzz")
        #expect(result == SearchResult())
    }

    @Test func randomSongsDecode() async throws {
        let songs = try await TestServer.client(FakeTransport(fixture: "getRandomSongs")).randomSongs(size: 2)
        #expect(songs.map(\.id) == ["so-3", "so-1"])
    }

    @Test func missingSingleItemIsADecodingError() async {
        let transport = FakeTransport(.json(TestServer.ok))
        do {
            _ = try await TestServer.client(transport).album(id: "al-1")
            Issue.record("Expected a decoding error")
        } catch {
            guard case .decoding = error else {
                Issue.record("Expected a decoding error, got \(error)")
                return
            }
        }
    }
}
