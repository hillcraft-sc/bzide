import Foundation
import Testing
@testable import NavidromeCore

/// Lets tests move the clock forward.
private final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
struct PlayHistoryTests {
    private let file = URL.temporaryDirectory.appending(path: "PlayHistoryTests-\(UUID().uuidString).json")
    private let defaults = UserDefaults(suiteName: "PlayHistoryTests-\(UUID().uuidString)")!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 2026-10-11 15:00 UTC.
    private let clock = TestClock(Date(timeIntervalSince1970: 1_791_730_800))

    /// Every play listed, unless a test turns combining back on.
    private func makeHistory() -> PlayHistory {
        let history = PlayHistory(fileURL: file, defaults: defaults, calendar: calendar, now: { [clock] in clock.now })
        history.combinesRepeats = false
        return history
    }

    /// The history as the next launch reads it. Saves are written in the
    /// background, so they're waited for first, as the app does before
    /// moving the files; a real relaunch comes long after them.
    private func relaunch() -> PlayHistory {
        FileWriters.drainAll()
        return makeHistory()
    }

    private func song(_ id: String, title: String = "Song", artist: String? = "Artist", album: String? = "Album") -> Song {
        Song(id: id, title: title, album: album, artist: artist)
    }

    private func daysAgo(_ days: Double, hours: Double = 0) -> Date {
        clock.now.addingTimeInterval(-(days * 86_400 + hours * 3_600))
    }

    @Test func playsAreKeptNewestFirst() {
        let history = makeHistory()
        history.record(song("so-1"), playedAt: daysAgo(0, hours: 2))
        history.record(song("so-2"), playedAt: daysAgo(0, hours: 1))
        history.record(song("so-3"), playedAt: daysAgo(0, hours: 3))
        #expect(history.entries.map(\.song.id) == ["so-2", "so-1", "so-3"])
    }

    @Test func historySurvivesARelaunch() {
        makeHistory().record(song("so-1"), playedAt: daysAgo(1))
        #expect(relaunch().entries.map(\.song.id) == ["so-1"])
    }

    @Test func playsOlderThanTheRetentionAreDropped() {
        let history = makeHistory()
        #expect(history.retention == .month)
        history.record(song("old"), playedAt: daysAgo(31))
        history.record(song("recent"), playedAt: daysAgo(29))
        #expect(history.entries.map(\.song.id) == ["recent"])

        history.retention = .week
        #expect(history.entries.isEmpty)
    }

    @Test func pruningAlsoHappensAtLaunch() {
        let history = makeHistory()
        history.retention = .forever
        history.record(song("old"), playedAt: daysAgo(40))

        defaults.set(HistoryRetention.month.rawValue, forKey: PlayHistory.retentionKey)
        #expect(relaunch().entries.isEmpty)
    }

    @Test func retentionIsRemembered() {
        makeHistory().retention = .year
        #expect(makeHistory().retention == .year)
    }

    @Test func clearRemovesEverything() {
        let history = makeHistory()
        history.record(song("so-1"), playedAt: daysAgo(0, hours: 1))
        history.clear()
        #expect(history.entries.isEmpty)
        #expect(relaunch().entries.isEmpty)
    }

    @Test func filtersByTrackArtistAndAlbum() {
        let history = makeHistory()
        history.record(song("so-1", title: "Dawn Chorus", artist: "Aurora Lines", album: "First Light"), playedAt: daysAgo(0, hours: 1))
        history.record(song("so-2", title: "Night", artist: "Other", album: "Café Nights"), playedAt: daysAgo(0, hours: 2))
        let ids = { (query: String) in history.days(matching: query, in: .all).flatMap(\.entries).map(\.song.id) }
        #expect(ids("chorus") == ["so-1"])
        #expect(ids("aurora") == ["so-1"])
        #expect(ids("first light") == ["so-1"])
        #expect(ids("cafe") == ["so-2"])
        #expect(ids("") == ["so-1", "so-2"])
    }

    @Test func filtersByPeriodAndGroupsByDay() {
        let history = makeHistory()
        history.retention = .forever
        history.record(song("today"), playedAt: daysAgo(0, hours: 1))
        history.record(song("yesterday"), playedAt: daysAgo(1))
        history.record(song("lastWeek"), playedAt: daysAgo(5))
        history.record(song("lastMonth"), playedAt: daysAgo(20))
        history.record(song("older"), playedAt: daysAgo(100))
        let ids = { (period: HistoryPeriod) in history.days(matching: "", in: period).flatMap(\.entries).map(\.song.id) }

        #expect(ids(.today) == ["today"])
        #expect(ids(.lastWeek) == ["today", "yesterday", "lastWeek"])
        #expect(ids(.lastMonth) == ["today", "yesterday", "lastWeek", "lastMonth"])
        #expect(ids(.all).count == 5)

        let days = history.days(matching: "", in: .lastWeek)
        #expect(days.count == 3)
        #expect(days.first?.day == calendar.startOfDay(for: clock.now))
    }

    @Test func customPeriodCoversWholeDaysInEitherOrder() {
        let history = makeHistory()
        history.record(song("in"), playedAt: daysAgo(3, hours: -8))
        history.record(song("out"), playedAt: daysAgo(6))
        let range = HistoryPeriod.custom(from: daysAgo(2), to: daysAgo(4))
        #expect(history.days(matching: "", in: range).flatMap(\.entries).map(\.song.id) == ["in"])
    }

    @Test func theEngineRecordsAPlayWhenItCountsForScrobbling() {
        let history = makeHistory()
        let player = FakeAudioPlayer()
        let engine = PlaybackEngine(
            player: player, session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: FakeStreamURLs(),
            store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler(),
            history: history, now: { [clock] in clock.now }
        )
        let songs = [Song(id: "so-1", title: "Dawn", duration: 60), Song(id: "so-2", title: "Noon", duration: 60)]
        engine.play(songs: songs)

        var time = 0.0
        while time < 29 {
            time += 0.5
            player.report(.timeChanged(time))
        }
        #expect(history.entries.isEmpty)

        while time < 40 {
            time += 0.5
            player.report(.timeChanged(time))
        }
        #expect(history.entries.map(\.song.title) == ["Dawn"])
        #expect(history.entries.first?.playedAt == clock.now)

        // Skipped before it counted: not recorded.
        player.finishCurrentItem()
        player.report(.timeChanged(5))
        player.finishCurrentItem()
        #expect(history.entries.count == 1)
    }

    @Test func repeatsAreCombinedByDefault() {
        #expect(PlayHistory(fileURL: file, defaults: UserDefaults(suiteName: "PlayHistoryTests-\(UUID().uuidString)")!).combinesRepeats)
    }

    @Test func combiningShowsEachSongOncePerDayAtItsLatestPlay() {
        let history = makeHistory()
        history.retention = .forever
        history.record(song("so-1", title: "Dawn"), playedAt: daysAgo(0, hours: 3))
        history.record(song("so-2", title: "Noon"), playedAt: daysAgo(0, hours: 2))
        history.record(song("so-1", title: "Dawn"), playedAt: daysAgo(0, hours: 1))
        history.record(song("so-1", title: "Dawn"), playedAt: daysAgo(1))
        history.combinesRepeats = true

        let days = history.days(matching: "", in: .all)
        #expect(days.count == 2)
        let today = days[0].items
        #expect(today.map(\.entry.song.id) == ["so-1", "so-2"])
        #expect(today.map(\.playCount) == [2, 1])
        #expect(today.first?.entry.playedAt == daysAgo(0, hours: 1))
        // Another day keeps its own row.
        #expect(days[1].items.map(\.playCount) == [1])
    }

    @Test func showingEveryPlayListsRepeatsSeparately() {
        let history = makeHistory()
        history.record(song("so-1"), playedAt: daysAgo(0, hours: 2))
        history.record(song("so-1"), playedAt: daysAgo(0, hours: 1))
        #expect(history.days(matching: "", in: .all).first?.items.map(\.playCount) == [1, 1])
    }

    @Test func combiningCountsOnlyPlaysThatMatchTheFilters() {
        let history = makeHistory()
        history.record(song("so-1", title: "Dawn"), playedAt: daysAgo(0, hours: 2))
        history.record(song("so-1", title: "Dawn"), playedAt: daysAgo(0, hours: 1))
        history.record(song("so-2", title: "Noon"), playedAt: daysAgo(0, hours: 1))
        history.combinesRepeats = true
        let items = history.days(matching: "dawn", in: .today).flatMap(\.items)
        #expect(items.map(\.playCount) == [2])
    }

    @Test func theChoiceIsRemembered() {
        makeHistory().combinesRepeats = false
        let reopened = PlayHistory(fileURL: file, defaults: defaults, calendar: calendar, now: { [clock] in clock.now })
        #expect(!reopened.combinesRepeats)
    }
}
