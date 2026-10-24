import Foundation
import Testing
@testable import NavidromeCore

/// The Wishlist's sections: songs from the radio, songs missing from
/// albums, albums and artists (Gitea #33).
@MainActor
struct WishlistKindsTests {
    private let defaults = UserDefaults(suiteName: "WishlistKindsTests-\(UUID().uuidString)")!
    private let file = URL.temporaryDirectory.appending(path: "WishlistKindsTests-\(UUID().uuidString)/Wishlist.json")

    private func wishlist(library: SearchResult = SearchResult()) -> Wishlist {
        Wishlist(
            fileURL: file, defaults: defaults,
            search: { _ async throws(SubsonicError) in [] },
            searchLibrary: { _ async throws(SubsonicError) in library }
        )
    }

    @Test func listsSavedBeforeKindsAreRadioSongs() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = #"[{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","artist":"Blur","title":"Song 2","heardAt":700000000}]"#
        try Data(old.utf8).write(to: file)
        let list = wishlist()
        #expect(list.entries.map(\.kind) == [.radioSong])
        #expect(list.sections.map(\.kind) == [.radioSong])
    }

    @Test func sectionsComeInOrderAndOnlyWithSomethingInThem() {
        let list = wishlist()
        list.addArtist(named: "Glass Harbor", musicBrainzURL: nil)
        list.add(OnAirSong(artist: "Blur", title: "Song 2"), station: "Alt FM", details: nil)
        #expect(list.sections.map(\.kind) == [.radioSong, .artist])
        #expect(list.sections.map(\.kind.sectionTitle) == ["Found on Radio", "Artists"])
    }

    @Test func missingSongsAreAddedOnceInTheAlbumsOrder() {
        let list = wishlist()
        list.add(OnAirSong(artist: "Looking Glass", title: "Jenny-Lynne"), station: nil, details: nil)
        let added = list.addMissingSongs(
            ["Golden Rainbow", "Jenny-Lynne", "Catherine Street", "Golden Rainbow"],
            album: "Looking Glass", artist: "Looking Glass", year: 1972, coverURL: nil, musicBrainzURL: nil
        )
        // Jenny-Lynne is already there (from the radio); a repeat counts once.
        #expect(added == 2)
        #expect(list.notice == "Added 2 songs to your Wishlist.")
        let missing = list.entries.filter { $0.kind == .missingSong }
        #expect(missing.map(\.title) == ["Golden Rainbow", "Catherine Street"])
        #expect(missing.first?.album == "Looking Glass")
        #expect(list.addMissingSongs(["Golden Rainbow"], album: "Looking Glass", artist: "Looking Glass", year: nil, coverURL: nil, musicBrainzURL: nil) == 0)
        #expect(list.notice == "Those songs are already on your Wishlist.")
    }

    @Test func albumsAndArtistsAreAddedOnce() {
        let list = wishlist()
        list.addAlbum(titled: "Weathered", by: "Creed", year: 2001, coverURL: nil, musicBrainzURL: nil)
        list.addAlbum(titled: "Weathered (Remastered)", by: "creed", year: nil, coverURL: nil, musicBrainzURL: nil)
        list.addArtist(named: "Glass Harbor", musicBrainzURL: nil)
        list.addArtist(named: "glass harbor", musicBrainzURL: nil)
        #expect(list.entries.filter { $0.kind == .album }.count == 1)
        #expect(list.entries.filter { $0.kind == .artist }.count == 1)
        #expect(list.containsAlbum(titled: "Weathered", by: "Creed"))
        #expect(list.containsArtist(named: "Glass Harbor"))
        #expect(list.entries.first { $0.kind == .artist }?.text == "Glass Harbor")
    }

    @Test func albumsAndArtistsFoundInTheLibraryAreMarked() async {
        let album = Album(id: "al-9", name: "Weathered", artist: "Creed")
        let artist = Artist(id: "ar-9", name: "Glass Harbor")
        let list = wishlist(library: SearchResult(artists: [artist], albums: [album]))
        list.addAlbum(titled: "Weathered", by: "Creed", year: nil, coverURL: nil, musicBrainzURL: nil)
        list.addArtist(named: "Glass Harbor", musicBrainzURL: nil)
        list.addAlbum(titled: "Human Clay", by: "Creed", year: nil, coverURL: nil, musicBrainzURL: nil)
        await list.checkLibrary()
        let byTitle = Dictionary(uniqueKeysWithValues: list.entries.map { ($0.title, list.found[$0.id]) })
        #expect(byTitle["Weathered"] == .some(.album(album)))
        #expect(byTitle["Glass Harbor"] == .some(.artist(artist)))
        #expect(byTitle["Human Clay"] == .some(nil))
        #expect(list.entries.first { $0.title == "Weathered" }?.foundAt != nil)
    }

    @Test func theMissingTracksAreTheReleasesTracksNotOwned() {
        let owned = [Song(id: "s2", title: "Brandy (You're a Fine Girl)")]
        let tracklist = [
            ReleaseTrack(disc: 1, number: 1, title: "Golden Rainbow"),
            ReleaseTrack(disc: 1, number: 2, title: "Brandy (You’re a Fine Girl)"),
            ReleaseTrack(disc: 1, number: 3, title: "Jenny-Lynne"),
        ]
        #expect(AlbumCompleteness.missingTracks(tracklist, owned: owned).map(\.title) == ["Golden Rainbow", "Jenny-Lynne"])
    }

    @Test func missingTracksNumberByDiscOnlyWhenThereAreSeveral() {
        let track = ReleaseTrack(disc: 2, number: 3, title: "Eye in the Sky")
        let release = ReleaseTracks(id: "r", title: "Weathered", trackCount: 20)
        #expect(MissingTracks(tracks: [track], release: release, isMultiDisc: true).number(of: track) == "2-3")
        #expect(MissingTracks(tracks: [track], release: release).number(of: track) == "3")
    }

    @Test func theReleaseIsTheTaggedOneElseTheSmallestEdition() {
        let releases = [ReleaseTracks(id: "big", title: "Weathered", trackCount: 14), ReleaseTracks(id: "small", title: "Weathered", trackCount: 11)]
        var album = Album(id: "al-1", name: "Weathered")
        #expect(AlbumCompleteness.release(for: album, among: releases)?.id == "small")
        album.musicBrainzID = "big"
        #expect(AlbumCompleteness.release(for: album, among: releases)?.id == "big")
    }

    @Test func aTracklistSkipsVideo() throws {
        let json = #"""
        {"media": [
          {"format": "CD", "position": 1, "tracks": [{"title": "Golden Rainbow", "position": 1}, {"title": "Brandy", "position": 2}]},
          {"format": "DVD-Video", "position": 2, "tracks": [{"title": "Brandy (video)", "position": 1}]},
          {"format": "CD", "tracks": [{"title": "Jenny-Lynne"}]}
        ]}
        """#
        let tracklist = try JSONDecoder().decode(MusicBrainzClient.ReleaseTracklist.self, from: Data(json.utf8))
        #expect(tracklist.tracks == [
            ReleaseTrack(disc: 1, number: 1, title: "Golden Rainbow"),
            ReleaseTrack(disc: 1, number: 2, title: "Brandy"),
            // No positions given: counted among the audio discs.
            ReleaseTrack(disc: 2, number: 1, title: "Jenny-Lynne"),
        ])
    }
}
