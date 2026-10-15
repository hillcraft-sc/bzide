import Foundation
import Testing
@testable import NavidromeCore

struct LyricsMatchingTests {
    // MARK: Cleaning titles

    @Test func versionNotesComeOff() {
        #expect(LyricsMatching.cleanTitle("My Evil Ways (2025 Remaster)") == "My Evil Ways")
        #expect(LyricsMatching.cleanTitle("Song - Single Version") == "Song")
        #expect(LyricsMatching.cleanTitle("Song [Explicit]") == "Song")
        #expect(LyricsMatching.cleanTitle("Song (feat. Someone Else)") == "Song")
        #expect(LyricsMatching.cleanTitle("Song feat. Someone Else") == "Song")
        #expect(LyricsMatching.cleanTitle("Song (2011)") == "Song")
        #expect(LyricsMatching.cleanTitle("Song (Deluxe Edition) [Remastered]") == "Song")
    }

    @Test func notesForAnotherPerformanceStay() {
        #expect(LyricsMatching.cleanTitle("Song (Live)") == "Song (Live)")
        #expect(LyricsMatching.cleanTitle("Song - Acoustic Version") == "Song - Acoustic Version")
        #expect(LyricsMatching.cleanTitle("Song (Club Remix)") == "Song (Club Remix)")
        // Parentheses that are part of the title stay too.
        #expect(LyricsMatching.cleanTitle("(Don't Fear) The Reaper") == "(Don't Fear) The Reaper")
    }

    @Test func namesCompareWithoutAccentsOrPunctuation() {
        #expect(LyricsMatching.normalize("Mötley Crüe") == LyricsMatching.normalize("Motley Crue"))
        #expect(LyricsMatching.normalize("Simon & Garfunkel") == LyricsMatching.normalize("Simon and Garfunkel"))
        #expect(LyricsMatching.normalize("AC/DC") == "ac dc")
    }

    // MARK: Scoring

    private let song = LyricsMatching.Song(title: "My Evil Ways (2025 Remaster)", artist: "Whitesnake", album: "Slide It In", duration: 200)

    private func candidate(
        title: String? = "My Evil Ways", artist: String? = "Whitesnake", album: String? = nil,
        duration: Double? = 200, synced: Bool = true
    ) -> LyricsMatching.Candidate {
        LyricsMatching.Candidate(title: title, artist: artist, album: album, duration: duration, isSynced: synced)
    }

    @Test func aMatchingRecordingScores() {
        #expect(LyricsMatching.score(candidate(), for: song) != nil)
    }

    @Test func otherRecordingsAreTurnedDown() {
        #expect(LyricsMatching.score(candidate(duration: 203), for: song) == nil)
        #expect(LyricsMatching.score(candidate(title: "Slow an' Easy"), for: song) == nil)
        #expect(LyricsMatching.score(candidate(artist: "Another Band"), for: song) == nil)
        #expect(LyricsMatching.score(candidate(title: "My Evil Ways (Live)"), for: song) == nil)
        // And a live song doesn't take studio lyrics.
        let live = LyricsMatching.Song(title: "My Evil Ways", artist: "Whitesnake", album: "Live in the Still of the Night", duration: 200)
        #expect(LyricsMatching.score(candidate(album: "Slide It In"), for: live) == nil)
        #expect(LyricsMatching.score(candidate(album: "Live in the Still of the Night"), for: live) != nil)
    }

    @Test func closerAndSameAlbumAndSyncedScoreHigher() throws {
        let exact = try #require(LyricsMatching.score(candidate(duration: 200), for: song))
        let off = try #require(LyricsMatching.score(candidate(duration: 201.5), for: song))
        let sameAlbum = try #require(LyricsMatching.score(candidate(album: "Slide It In", duration: 201.5), for: song))
        let plain = try #require(LyricsMatching.score(candidate(synced: false), for: song))
        #expect(exact > off)
        #expect(sameAlbum > off)
        #expect(exact > plain)
    }

    @Test func accentedArtistsMatch() {
        let crue = LyricsMatching.Song(title: "Kickstart My Heart", artist: "Motley Crue", album: nil, duration: 282)
        #expect(LyricsMatching.score(candidate(title: "Kickstart My Heart", artist: "Mötley Crüe", duration: 282), for: crue) != nil)
    }

    // MARK: The lookup

    private static func record(_ title: String, artist: String, duration: Double, synced: String) -> String {
        #"{"trackName":"\#(title)","artistName":"\#(artist)","duration":\#(duration),"syncedLyrics":"\#(synced)"}"#
    }

    @Test func aRemasterIsLookedUpWithoutItsNote() async throws {
        let transport = FakeTransport(.json("{}", status: 404), .json(Self.record("My Evil Ways", artist: "Whitesnake", duration: 200, synced: "[00:01.00] right")))
        let result = try await LRCLIBClient(transport: transport).lyrics(
            title: "My Evil Ways (2025 Remaster)", artist: "Whitesnake", album: "Slide It In", duration: 200
        )
        #expect(result?.synced == "[00:01.00] right")
        let titles = await transport.requests.compactMap { $0.url?.queryParameters["track_name"] }
        #expect(titles == ["My Evil Ways (2025 Remaster)", "My Evil Ways"])
    }

    @Test func theSearchKeepsTheBestMatchAndTurnsDownTheRest() async throws {
        let results = "[" + [
            Self.record("My Evil Ways", artist: "Whitesnake", duration: 202.5, synced: "[00:01.00] too long"),
            Self.record("My Evil Ways (Live)", artist: "Whitesnake", duration: 200, synced: "[00:01.00] live"),
            Self.record("My Evil Ways", artist: "Whitesnake", duration: 201, synced: "[00:01.00] close"),
            Self.record("My Evil Ways", artist: "Whitesnake", duration: 200, synced: "[00:01.00] exact"),
        ].joined(separator: ",") + "]"
        let transport = FakeTransport(.json("{}", status: 404), .json(results))
        let result = try await LRCLIBClient(transport: transport).lyrics(title: "My Evil Ways", artist: "Whitesnake", album: nil, duration: 200)
        #expect(result?.synced == "[00:01.00] exact")
    }

    @Test func noGoodMatchIsNoLyrics() async throws {
        let results = "[" + Self.record("My Evil Ways (Live)", artist: "Whitesnake", duration: 260, synced: "[00:01.00] wrong") + "]"
        let transport = FakeTransport(.json("{}", status: 404), .json(results))
        #expect(try await LRCLIBClient(transport: transport).lyrics(title: "My Evil Ways", artist: "Whitesnake", album: nil, duration: 200) == nil)
    }
}

@MainActor
struct LyricsTimingFixTests {
    private func store() -> (LyricsTiming, UserDefaults) {
        let defaults = UserDefaults(suiteName: "LyricsTimingTests-\(UUID().uuidString)")!
        return (LyricsTiming(defaults: defaults), defaults)
    }

    @Test func nudgesEarlierAndLaterAndResets() {
        let (timing, _) = store()
        #expect(timing.offset(for: "so-1") == 0)
        timing.earlier("so-1")
        timing.earlier("so-1")
        #expect(timing.offset(for: "so-1") == 1)
        timing.later("so-1")
        #expect(timing.offset(for: "so-1") == 0.5)
        timing.reset("so-1")
        #expect(timing.offset(for: "so-1") == 0)
        #expect(timing.offsets.isEmpty)
    }

    @Test func rememberedForTheSong() {
        let (timing, defaults) = store()
        timing.later("so-1")
        #expect(LyricsTiming(defaults: defaults).offset(for: "so-1") == -0.5)
        #expect(LyricsTiming(defaults: defaults).offset(for: "so-2") == 0)
    }

    @Test func describesTheShift() {
        #expect(LyricsTiming.describe(0) == nil)
        #expect(LyricsTiming.describe(1.5) == "1.5 s earlier")
        #expect(LyricsTiming.describe(-0.5) == "0.5 s later")
    }

    @Test func staysWithinLimits() {
        let (timing, _) = store()
        for _ in 0..<100 { timing.earlier("so-1") }
        #expect(timing.offset(for: "so-1") == LyricsTiming.limit)
    }

    @Test func forgetsTheOldestFixesBeyondItsLimit() {
        let (timing, _) = store()
        for index in 0...LyricsTiming.maximumSongs {
            timing.earlier("so-\(index)")
        }
        #expect(timing.offsets.count == LyricsTiming.maximumSongs)
        #expect(timing.offset(for: "so-0") == 0)
    }
}
