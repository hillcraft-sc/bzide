import Foundation
import Testing
@testable import NavidromeCore

struct AlbumCarouselTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func album(
        _ id: String, artist: String = "Band", rating: Int? = nil, starred: Bool = false,
        plays: Int? = nil, daysAgo: Double? = nil
    ) -> Album {
        var album = Album(id: id, name: id, artist: artist, artistID: artist, isStarred: starred, userRating: rating)
        album.details.playCount = plays
        album.details.lastPlayed = daysAgo.map { now.addingTimeInterval(-$0 * day) }
        return album
    }

    // MARK: Recently Played

    @Test func recentlyPlayedIsTheLastWeekNewestFirst() {
        let recent = [album("a", daysAgo: 3), album("b", daysAgo: 0.5), album("c", daysAgo: 9), album("d", daysAgo: 6.9)]
        #expect(RecentlyPlayed.albums(from: recent, now: now).map(\.id) == ["b", "a", "d"])
    }

    @Test func withoutPlayDatesItShowsTheMostRecent() {
        let recent = (1...20).map { album("al-\($0)") }
        #expect(RecentlyPlayed.albums(from: recent, now: now).count == RecentlyPlayed.fallbackCount)
    }

    @Test func albumsReadWhenTheyWereLastPlayed() throws {
        let json = #"{"id":"al-1","name":"Album","played":"2026-10-12T21:15:00Z","playCount":4}"#
        let decoded = try JSONDecoder().decode(Album.self, from: Data(json.utf8))
        #expect(decoded.details.lastPlayed == MediaDates.date("2026-10-12T21:15:00Z"))
        #expect(decoded.details.playCount == 4)
    }

    // MARK: Spin It Back

    @Test func likedAlbumsNotPlayedLatelyComeFirst() {
        let albums = [
            album("loved-long-ago", artist: "A", rating: 5, daysAgo: 300),
            album("loved-yesterday", artist: "B", rating: 5, daysAgo: 1),
            album("unrated-unplayed", artist: "C"),
            album("played-a-lot", artist: "D", plays: 40, daysAgo: 200),
        ]
        let picks = SpinItBack.picks(from: albums, now: now).map(\.id)
        #expect(picks.first == "loved-long-ago")
        // Not liked at all: never suggested. Played yesterday: last.
        #expect(!picks.contains("unrated-unplayed"))
        #expect(picks.last == "loved-yesterday")
    }

    @Test func mehAlbumsAreNeverSuggested() {
        let picks = SpinItBack.picks(from: [album("meh", rating: 2, starred: true, plays: 50, daysAgo: 400)], now: now)
        #expect(picks.isEmpty)
    }

    @Test func atMostTwoPerArtist() {
        let albums = (1...5).map { album("al-\($0)", artist: "Same", rating: 5, daysAgo: 200) } + [album("other", artist: "Other", rating: 3, daysAgo: 200)]
        let picks = SpinItBack.picks(from: albums, now: now)
        #expect(picks.filter { $0.artist == "Same" }.count == 2)
        #expect(picks.contains { $0.id == "other" })
    }

    @Test func itHoldsStillWithinADayAndChangesBetweenDays() {
        let albums = (1...40).map { album("al-\($0)", artist: "Artist \($0)", rating: 3, daysAgo: 100) }
        let morning = SpinItBack.picks(from: albums, now: now).map(\.id)
        let evening = SpinItBack.picks(from: albums, now: now.addingTimeInterval(3 * 60 * 60)).map(\.id)
        let tomorrow = SpinItBack.picks(from: albums, now: now.addingTimeInterval(day)).map(\.id)
        #expect(morning.count == SpinItBack.count)
        #expect(morning == evening || Calendar.current.isDate(now, inSameDayAs: now.addingTimeInterval(3 * 60 * 60)) == false)
        #expect(morning != tomorrow)
    }

    @Test func timeAwayGrowsUpToAYear() {
        #expect(SpinItBack.timeAway(now.addingTimeInterval(-3 * day), now: now) == 0.05)
        #expect(SpinItBack.timeAway(now.addingTimeInterval(-400 * day), now: now) == 1)
        let middle = SpinItBack.timeAway(now.addingTimeInterval(-180 * day), now: now)
        #expect(middle > 0.3 && middle < 1)
        #expect(SpinItBack.timeAway(nil, now: now) == 0.4)
    }

    @Test func aServerWithoutPlayHistoryUsesMostPlayedLessRecent() {
        let frequent = (1...20).map { album("al-\($0)") }
        let recent = [album("al-1"), album("al-3")]
        let picks = SpinItBack.fallback(frequent: frequent, recent: recent).map(\.id)
        #expect(!picks.contains("al-1") && !picks.contains("al-3"))
        #expect(picks.count == SpinItBack.count)
    }
}
