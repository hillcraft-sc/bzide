import Foundation
import Testing
@testable import NavidromeCore

struct RadioStationTests {
    @Test func decodesStationsAndDropsUnplayableOnes() async throws {
        let transport = try FakeTransport(fixture: "getInternetRadioStations")
        let stations = try await TestServer.client(transport).radioStations()
        #expect(stations.map(\.id) == ["rs-1", "rs-2", "rs-3"])
        #expect(stations[0] == RadioStation(
            id: "rs-1", name: "Night Waves",
            streamURL: URL(string: "https://stream.example.com/nightwaves.mp3")!,
            homePageURL: URL(string: "https://example.com/nightwaves")!
        ))
        #expect(stations[1].streamURL.absoluteString == "http://radio.example.org:8000/live")
        // No name: the stream's host stands in. A homepage that isn't a URL is dropped.
        #expect(stations[2].name == "listen.example.net")
        #expect(stations[2].homePageURL == nil)

        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/rest/getInternetRadioStations")
    }

    @Test func noStationsIsAnEmptyList() async throws {
        let stations = try await TestServer.client(FakeTransport(.json(TestServer.ok))).radioStations()
        #expect(stations.isEmpty)
    }

    @Test func aStationIsAQueueEntryThatSurvivesSaving() throws {
        let station = RadioStation(id: "rs-1", name: "Night Waves", streamURL: URL(string: "https://example.com/a.pls")!)
        let song = Song(station: station, stream: URL(string: "https://stream.example.com/live")!)
        #expect(song.id == "radio:rs-1")
        #expect(song.title == "Night Waves")
        #expect(song.isLive)

        let decoded = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(song))
        #expect(decoded == song)
        // An ordinary song stays ordinary.
        let plain = Song(id: "so-1", title: "Dawn")
        #expect(try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(plain)).isLive == false)
    }
}

struct RadioPlaylistTests {
    private func station(_ address: String) -> RadioStation {
        RadioStation(id: "rs-1", name: "Station", streamURL: URL(string: address)!)
    }

    private static func serving(_ text: String) -> RadioPlaylist.Fetch {
        { _ in Data(text.utf8) }
    }

    @Test func directStreamsAndHLSGoStraightToThePlayer() async throws {
        for address in ["http://radio.example.org:8000/live", "https://example.com/stream.mp3", "https://example.com/live.m3u8"] {
            let url = try await RadioPlaylist.streamURL(for: station(address)) { _ in
                Issue.record("Nothing should be fetched for \(address)")
                return Data()
            }
            #expect(url.absoluteString == address)
        }
    }

    @Test func plsGivesTheLowestNumberedFile() async throws {
        let pls = """
        [playlist]
        NumberOfEntries=2
        File2=https://backup.example.com/live
        Title2=Backup
        File1=https://main.example.com/live
        Version=2
        """
        let url = try await RadioPlaylist.streamURL(for: station("https://example.com/station.pls"), fetch: Self.serving(pls))
        #expect(url.absoluteString == "https://main.example.com/live")
    }

    @Test func m3uGivesTheFirstLineThatIsntAComment() async throws {
        let m3u = "#EXTM3U\r\n#EXTINF:-1,Station\r\n\r\nhttp://stream.example.com:8000/live\r\nhttp://other.example.com/live\r\n"
        let url = try await RadioPlaylist.streamURL(for: station("https://example.com/listen.M3U"), fetch: Self.serving(m3u))
        #expect(url.absoluteString == "http://stream.example.com:8000/live")
    }

    @Test func anInsecurePlaylistFileCantBeRead() async {
        await #expect(throws: RadioPlaylist.ResolveError.insecurePlaylist) {
            try await RadioPlaylist.streamURL(for: station("http://example.com/station.pls"), fetch: Self.serving(""))
        }
    }

    @Test func aPlaylistWithoutAStreamSaysSo() async {
        await #expect(throws: RadioPlaylist.ResolveError.noStreamInPlaylist) {
            try await RadioPlaylist.streamURL(for: station("https://example.com/s.pls"), fetch: Self.serving("[playlist]\nNumberOfEntries=0"))
        }
    }

    @Test func anUnreachablePlaylistSaysWhy() async {
        struct Offline: Error {}
        do {
            _ = try await RadioPlaylist.streamURL(for: station("https://example.com/s.m3u")) { _ in throw Offline() }
            Issue.record("Expected an error")
        } catch {
            guard case .unreachable = error else {
                Issue.record("Expected unreachable, got \(error)")
                return
            }
        }
    }
}

@MainActor
struct RadioPlayerTests {
    private final class Played {
        var songs: [Song] = []
    }

    @Test func startingResolvesThenPlaysTheStation() async {
        let played = Played()
        let radio = RadioPlayer(fetchPlaylist: { _ in Data("File1=https://main.example.com/live".utf8) }) { played.songs.append($0) }
        let station = RadioStation(id: "rs-1", name: "Night Waves", streamURL: URL(string: "https://example.com/s.pls")!)
        await radio.start(station)
        #expect(played.songs.map(\.liveStreamURL?.absoluteString) == ["https://main.example.com/live"])
        #expect(radio.startingStationID == nil)
        #expect(radio.error == nil)
    }

    @Test func aStationThatCantBeResolvedSaysWhyAndPlaysNothing() async {
        let played = Played()
        let radio = RadioPlayer(fetchPlaylist: { _ in Data() }) { played.songs.append($0) }
        await radio.start(RadioStation(id: "rs-1", name: "X", streamURL: URL(string: "http://example.com/s.pls")!))
        #expect(played.songs.isEmpty)
        #expect(radio.error == RadioPlaylist.ResolveError.insecurePlaylist.localizedDescription)
        radio.dismissError()
        #expect(radio.error == nil)
    }
}

final class FakePlayHistory: PlayRecording {
    private(set) var recorded: [Song] = []
    func record(_ song: Song, playedAt: Date) { recorded.append(song) }
}

@MainActor
struct EngineRadioTests {
    private let player = FakeAudioPlayer()
    private let nowPlaying = FakeNowPlaying()
    private let store = InMemoryQueueStore()
    private let scheduler = FakeScheduler()
    private let scrobbler = FakeScrobbler()
    private let history = FakePlayHistory()

    private let stream = URL(string: "http://radio.example.org:8000/live")!
    private var station: Song {
        Song(station: RadioStation(id: "rs-1", name: "Night Waves", streamURL: stream), stream: stream)
    }

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(
            player: player, session: FakeAudioSession(), nowPlaying: nowPlaying, urls: FakeStreamURLs(),
            store: store, scheduler: scheduler, network: FakeNetworkMonitor(), scrobbler: scrobbler, history: history
        )
    }

    @Test func playsTheStationsOwnStreamAsALiveItem() {
        let engine = makeEngine()
        engine.play(songs: [station])
        #expect(player.loaded.map(\.url) == [stream])
        #expect(player.loaded.first?.isLive == true)
        #expect(nowPlaying.latest?.isLiveStream == true)
        #expect(nowPlaying.latest?.title == "Night Waves")
        #expect(nowPlaying.latest?.duration == nil)
        #expect(nowPlaying.latest?.hasPrevious == false)
    }

    @Test func isNeverScrobbledOrAddedToHistory() {
        let engine = makeEngine()
        engine.play(songs: [station])
        player.report(.statusChanged(.playing))
        for second in stride(from: 0.0, through: 600, by: 10) {
            player.report(.timeChanged(second))
        }
        #expect(scrobbler.nowPlayingSongIDs.isEmpty)
        #expect(scrobbler.submitted.isEmpty)
        #expect(history.recorded.isEmpty)
        #expect(engine.status == .playing)
    }

    @Test func cantSeekOrGoBackOrTakeADuration() {
        let engine = makeEngine()
        engine.play(songs: [station])
        player.report(.timeChanged(30))
        engine.seek(to: 10)
        engine.previous()
        player.report(.durationKnown(1234))
        #expect(player.seeks.isEmpty)
        #expect(engine.duration == nil)
        #expect(player.setItemsCalls.count == 1)
        #expect(engine.status.isActive)
    }

    @Test func resumingAfterAPauseRejoinsLive() {
        let engine = makeEngine()
        engine.play(songs: [station])
        player.report(.timeChanged(300))
        engine.pause()
        engine.play()
        #expect(player.setItemsCalls.count == 2)
        #expect(player.setItemsCalls.last?.startPosition == 0)
        #expect(player.isPlaying)
    }

    @Test func aStreamThatEndsIsRetriedNotFinished() {
        let engine = makeEngine()
        engine.play(songs: [station])
        player.report(.statusChanged(.playing))
        player.finishCurrentItem()
        #expect(engine.status == .reconnecting)
        #expect(engine.queue.current?.song.id == "radio:rs-1")

        scheduler.fireNext()
        #expect(player.setItemsCalls.count == 2)
        #expect(player.setItemsCalls.last?.startPosition == 0)
    }

    @Test func showsWhatTheStationAnnounces() throws {
        let engine = makeEngine()
        engine.play(songs: [station])
        let entry = try #require(engine.queue.current?.id)

        #expect(engine.currentTitle == "Night Waves")
        #expect(engine.currentSubtitle == nil)
        #expect(engine.isLive)
        #expect(!engine.canGoNext)

        player.report(.streamTitle(entry, "  Artist - Song  "))
        #expect(engine.streamTitle == "Artist - Song")
        #expect(engine.currentTitle == "Artist - Song")
        #expect(engine.currentSubtitle == "Night Waves")
        #expect(nowPlaying.latest?.title == "Artist - Song")
        #expect(nowPlaying.latest?.artist == "Night Waves")

        player.report(.streamTitle(entry, ""))
        #expect(engine.streamTitle == nil)
        #expect(nowPlaying.latest?.title == "Night Waves")
        #expect(nowPlaying.latest?.artist == nil)
    }

    @Test func songsIgnoreStreamTitlesAndAStationChangeClearsIt() throws {
        let engine = makeEngine()
        engine.play(songs: [Song(id: "so-1", title: "Dawn", duration: 200)])
        player.report(.streamTitle(try #require(engine.queue.current?.id), "Ignored"))
        #expect(engine.streamTitle == nil)

        engine.play(songs: [station])
        player.report(.streamTitle(try #require(engine.queue.current?.id), "On Air"))
        engine.play(songs: [Song(id: "so-1", title: "Dawn", duration: 200)])
        #expect(engine.streamTitle == nil)
    }

    @Test func nothingIsPreloadedBehindAStation() {
        let engine = makeEngine()
        engine.play(songs: [station])
        engine.append([Song(id: "so-1", title: "Dawn")])
        #expect(player.loaded.count == 1)
        // Next still moves on to it.
        engine.next()
        #expect(engine.queue.current?.song.id == "so-1")
        #expect(player.loaded.first?.isLive == false)
    }

    @Test func aRestoredStationComesBackPausedAtLive() {
        store.save(QueueSnapshot(queue: PlaybackQueue(songs: [station]), position: 900))
        let engine = makeEngine()
        #expect(engine.status == .paused)
        #expect(engine.position == 0)
        #expect(player.setItemsCalls.isEmpty)
        engine.play()
        #expect(player.setItemsCalls.last?.startPosition == 0)
        #expect(player.loaded.map(\.url) == [stream])
    }
}
