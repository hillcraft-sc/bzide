import Foundation
import Testing
@testable import NavidromeCore

struct MediaInfoTests {
    private let locale = Locale(identifier: "en_US")

    /// A song as Navidrome describes it, with OpenSubsonic extras.
    private let richSong = #"""
    {"id":"so-1","title":"Morning Static","album":"Placeholder Album","artist":"The Placeholders","track":4,"discNumber":2,
     "year":1993,"genre":"Rock","duration":291,"bitRate":964,"suffix":"flac","size":64172342,"playCount":14,
     "created":"2026-03-03T12:00:00.000Z","played":"2026-10-12T21:15:00Z","samplingRate":96000,"bitDepth":24,
     "channelCount":2,"bpm":0,"comment":"","displayComposer":"A. Writer","displayAlbumArtist":"Various Placeholders",
     "genres":[{"name":"Rock"},{"name":"Grunge"}],"moods":["Brooding"],"userRating":5,"starred":"2026-04-01T00:00:00Z",
     "replayGain":{"trackGain":-6.1,"albumGain":-5.8}}
    """#

    private func song(_ json: String) throws -> Song {
        try JSONDecoder().decode(Song.self, from: Data(json.utf8))
    }

    @Test func readsTheExtraDetails() throws {
        let details = try song(richSong).details
        #expect(details.size == 64_172_342)
        #expect(details.playCount == 14)
        #expect(details.sampleRate == 96_000)
        #expect(details.bitDepth == 24)
        #expect(details.channels == 2)
        // 0 means unknown, and an empty comment is no comment.
        #expect(details.bpm == nil)
        #expect(details.comment == nil)
        #expect(details.genres == ["Rock", "Grunge"])
        #expect(details.moods == ["Brooding"])
        #expect(details.composer == "A. Writer")
        #expect(details.added == MediaDates.date("2026-03-03T12:00:00Z"))
        #expect(details.lastPlayed != nil)
    }

    @Test func aPlainSubsonicSongHasNoExtras() throws {
        let plain = try song(#"{"id":"so-2","title":"Bare","artist":"Someone","duration":200}"#)
        #expect(plain.details == SongDetails())
        let sections = MediaInfo.sections(for: plain, locale: locale)
        #expect(sections.map(\.title) == ["General"])
        #expect(sections[0].rows.map(\.label) == ["Title", "Artist", "Length"])
    }

    @Test func theDetailsAreKeptWithTheSavedQueue() throws {
        let original = try song(richSong)
        let saved = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(original))
        #expect(saved.details == original.details)
    }

    @Test func aSongsInfoScreen() throws {
        let sections = MediaInfo.sections(for: try song(richSong), locale: locale)
        #expect(sections.map(\.title) == ["General", "Audio", "Library"])
        let values = Dictionary(uniqueKeysWithValues: sections.flatMap(\.rows).map { ($0.label, $0.value) })
        #expect(values["Album Artist"] == "Various Placeholders")
        #expect(values["Track"] == "4 (disc 2)")
        #expect(values["Genres"] == "Rock, Grunge")
        #expect(values["Length"] == "4:51")
        #expect(values["Format"] == "FLAC")
        #expect(values["Resolution"] == "24-bit / 96 kHz")
        #expect(values["Channels"] == "Stereo")
        #expect(values["Bitrate"] == "964 kbps")
        #expect(values["Size"] == "64.2 MB")
        #expect(values["ReplayGain"] == "Track \u{2212}6.1 dB · Album \u{2212}5.8 dB")
        #expect(values["Plays"] == "14")
        #expect(values["Added"] == "Mar 3, 2026")
        #expect(values["Rating"] == "Love")
        #expect(values["Favorite"] == "Yes")
        #expect(values["BPM"] == nil)
        #expect(values["Comment"] == nil)
    }

    @Test func formatsThePieces() {
        #expect(MediaInfo.resolution(bitDepth: nil, sampleRate: 44_100, locale: locale) == "44.1 kHz")
        #expect(MediaInfo.resolution(bitDepth: 16, sampleRate: nil, locale: locale) == "16-bit")
        #expect(MediaInfo.resolution(bitDepth: nil, sampleRate: nil, locale: locale) == nil)
        #expect(MediaInfo.trackPosition(track: 3, disc: 1) == "3")
        #expect(MediaInfo.trackPosition(track: 0, disc: 1) == nil)
        #expect(MediaInfo.channels(1) == "Mono")
        #expect(MediaInfo.channels(6) == "6 channels")
        #expect(MediaInfo.clock(3_725) == "1:02:05")
        #expect(MediaInfo.length(2_470, locale: locale) == "41 min")
        #expect(MediaInfo.length(4_320, locale: locale) == "1 hr 12 min")
        #expect(MediaInfo.length(3_600, locale: locale) == "1 hr")
        #expect(MediaDates.date("2026-03-03T12:00:00Z") != nil)
        #expect(MediaDates.date("not a date") == nil)
    }

    private let richAlbum = #"""
    {"id":"al-1","name":"Placeholder Album","artist":"The Placeholders","year":1993,"genre":"Rock","songCount":12,
     "duration":2470,"playCount":31,"created":"2026-03-03T12:00:00Z","recordLabels":[{"name":"Invented Records"}],
     "releaseTypes":["album","live"],"originalReleaseDate":{"year":1991,"month":5},"genres":[{"name":"Rock"}],
     "isCompilation":false}
    """#

    @Test func anAlbumsInfoAndHeader() throws {
        let album = try JSONDecoder().decode(Album.self, from: Data(richAlbum.utf8))
        #expect(album.details.labels == ["Invented Records"])
        #expect(album.details.originalYear == 1991)
        let values = Dictionary(uniqueKeysWithValues: MediaInfo.sections(for: album, locale: locale).flatMap(\.rows).map { ($0.label, $0.value) })
        #expect(values["Year"] == "1993 (originally 1991)")
        #expect(values["Release Type"] == "Album, Live")
        #expect(values["Label"] == "Invented Records")
        #expect(values["Plays"] == "31")
        // The label is in Album Info, not the header line.
        #expect(MediaInfo.albumDetailsLine(album, locale: locale) == "Rock · 12 songs · 41 min")
    }

    @Test func aPlainAlbumStillGetsAHeaderLine() throws {
        let album = try JSONDecoder().decode(Album.self, from: Data(#"{"id":"al-2","name":"Bare","songCount":1,"duration":200}"#.utf8))
        #expect(album.details == AlbumDetails())
        #expect(MediaInfo.albumDetailsLine(album, locale: locale) == "1 song · 3 min")
        let empty = try JSONDecoder().decode(Album.self, from: Data(#"{"id":"al-3","name":"Nothing"}"#.utf8))
        #expect(MediaInfo.albumDetailsLine(empty, locale: locale) == nil)
    }

    @Test func aPlainAlbumTypeIsntWorthSaying() throws {
        let album = try JSONDecoder().decode(Album.self, from: Data(#"{"id":"al-4","name":"Plain","releaseTypes":["album"],"isCompilation":true}"#.utf8))
        let values = Dictionary(uniqueKeysWithValues: MediaInfo.sections(for: album, locale: locale).flatMap(\.rows).map { ($0.label, $0.value) })
        #expect(values["Release Type"] == "Album, Compilation")
        let alone = try JSONDecoder().decode(Album.self, from: Data(#"{"id":"al-5","name":"Plain","releaseTypes":["album"]}"#.utf8))
        #expect(MediaInfo.sections(for: alone, locale: locale).flatMap(\.rows).contains { $0.label == "Release Type" } == false)
    }
}
