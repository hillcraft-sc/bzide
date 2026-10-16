import Foundation
import Testing
@testable import NavidromeCore

struct OnAirSongTests {
    @Test func announcedTitlesAreReadAsArtistAndTitle() {
        #expect(OnAirSong(announced: "Radiohead - Karma Police", stationName: "Alt FM") == OnAirSong(artist: "Radiohead", title: "Karma Police"))
        #expect(OnAirSong(announced: "  Björk – Hyperballad ", stationName: nil) == OnAirSong(artist: "Björk", title: "Hyperballad"))
        #expect(OnAirSong(announced: "Hyperballad by Björk", stationName: nil) == OnAirSong(artist: "Björk", title: "Hyperballad"))
        // Only the first dash splits: the rest belongs to the title.
        #expect(OnAirSong(announced: "Blur - Song 2 - Remastered", stationName: nil)?.title == "Song 2 - Remastered")
    }

    @Test func whatIsntASongIsLeftOut() {
        #expect(OnAirSong(announced: "", stationName: nil) == nil)
        #expect(OnAirSong(announced: "Alt FM", stationName: "Alt FM") == nil)
        #expect(OnAirSong(announced: "Visit www.altfm.example - now", stationName: nil) == nil)
        #expect(OnAirSong(announced: "Commercial Break - 2 min", stationName: nil) == nil)
        #expect(OnAirSong(announced: "Just Some Words", stationName: nil) == nil)
        #expect(OnAirSong(announced: " - Title", stationName: nil) == nil)
    }

    @Test func matchingIgnoresVersionNotesAccentsAndOrder() {
        let song = Song(id: "so-1", title: "Karma Police (Remastered)", artist: "Radiohead")
        #expect(OnAirSong(artist: "Radiohead", title: "Karma Police").matches(song))
        #expect(OnAirSong(artist: "RADIOHEAD", title: "karma police").matches(song))
        // A station that puts the title first.
        #expect(OnAirSong(artist: "Karma Police", title: "Radiohead").matches(song))
        #expect(OnAirSong(artist: "Radiohead feat. Someone", title: "Karma Police").matches(song))
        #expect(!OnAirSong(artist: "Radiohead", title: "Creep").matches(song))
        #expect(!OnAirSong(artist: "Coldplay", title: "Karma Police").matches(song))
        #expect(OnAirSong(artist: "Bjork", title: "Hyperballad").matches(Song(id: "so-2", title: "Hyperballad", artist: "Björk")))
    }
}

@MainActor
struct OnAirMatchModelTests {
    private actor Searches {
        var queries: [String] = []
        var failing = false
        func add(_ query: String) { queries.append(query) }
        func setFailing(_ value: Bool) { failing = value }
    }

    private static let karma = Song(id: "so-1", title: "Karma Police", albumID: "al-1", artist: "Radiohead")

    private func model(_ searches: Searches, results: [String: [Song]] = [:]) -> OnAirMatchModel {
        OnAirMatchModel { query async throws(SubsonicError) in
            await searches.add(query)
            if await searches.failing { throw .network(.notConnectedToInternet) }
            return results[query] ?? []
        }
    }

    @Test func aSongInTheLibraryIsFound() async {
        let searches = Searches()
        let onAir = model(searches, results: ["Radiohead Karma Police": [Song(id: "x", title: "Creep", artist: "Radiohead"), Self.karma]])
        await onAir.update(announced: "Radiohead - Karma Police", stationName: "Alt FM")
        #expect(onAir.onAir == OnAirSong(artist: "Radiohead", title: "Karma Police"))
        #expect(onAir.match == Self.karma)
        #expect(await searches.queries == ["Radiohead Karma Police"])
    }

    @Test func itTriesTheTitleThenTheArtistAlone() async {
        let searches = Searches()
        let onAir = model(searches, results: ["Radiohead": [Self.karma]])
        await onAir.update(announced: "Radiohead - Karma Police", stationName: nil)
        #expect(onAir.match == Self.karma)
        #expect(await searches.queries == ["Radiohead Karma Police", "Karma Police", "Radiohead"])
    }

    @Test func answersAreRememberedButFailuresArent() async {
        let searches = Searches()
        let onAir = model(searches)
        await onAir.update(announced: "Radiohead - Karma Police", stationName: nil)
        #expect(onAir.match == nil)
        let asked = await searches.queries.count
        await onAir.update(announced: "Radiohead - Karma Police", stationName: nil)
        #expect(await searches.queries.count == asked)

        await searches.setFailing(true)
        await onAir.update(announced: "Blur - Song 2", stationName: nil)
        await searches.setFailing(false)
        await onAir.update(announced: "Blur - Song 2", stationName: nil)
        // The failed search is asked again.
        #expect(await searches.queries.filter { $0 == "Blur Song 2" }.count == 2)
    }

    @Test func noTitleOrNotASongClearsTheMatch() async {
        let onAir = model(Searches(), results: ["Radiohead Karma Police": [Self.karma]])
        await onAir.update(announced: "Radiohead - Karma Police", stationName: nil)
        #expect(onAir.match != nil)
        await onAir.update(announced: "Alt FM", stationName: "Alt FM")
        #expect(onAir.match == nil)
        #expect(onAir.onAir == nil)
        await onAir.update(announced: nil, stationName: "Alt FM")
        #expect(onAir.match == nil)
    }
}
