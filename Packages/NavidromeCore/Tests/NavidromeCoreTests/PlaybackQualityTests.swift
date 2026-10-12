import Foundation
import Testing
@testable import NavidromeCore

struct PlaybackQualityLabelTests {
    @Test func labelsSayFormatBitrateAndSource() {
        #expect(PlaybackQuality(format: "flac", bitRate: 1411).label == "FLAC · 1,411 kbps")
        #expect(PlaybackQuality(format: "mp3", bitRate: 192, isConverted: true).label == "MP3 · 192 kbps · Converted")
        #expect(PlaybackQuality(format: "flac", bitRate: 1411, isDownloaded: true).label == "FLAC · 1,411 kbps · Downloaded")
        #expect(PlaybackQuality(format: "mp3", bitRate: nil, isConverted: true, isDownloaded: true).label == "MP3 · Converted · Downloaded")
        #expect(PlaybackQuality(format: nil, bitRate: nil).label == "Unknown quality")
    }
}

@MainActor
struct ResolverQualityTests {
    private let network = FakeNetworkCost()
    private let downloads = FakeDownloads()
    private let settings = StreamingSettingsModel(defaults: UserDefaults(suiteName: "ResolverQualityTests-\(UUID())")!)
    private let flac = Song(id: "so-1", title: "Dawn", bitRate: 1411, suffix: "flac")

    private func resolver() -> TrackResolver {
        TrackResolver(client: TestServer.client(FakeTransport()), settings: settings, network: network, downloads: downloads)
    }

    @Test func streamingTheOriginal() {
        #expect(resolver().quality(for: flac) == PlaybackQuality(format: "flac", bitRate: 1411))
    }

    @Test func streamingConvertedOnCellular() {
        network.isExpensive = true
        #expect(resolver().quality(for: flac) == PlaybackQuality(format: "mp3", bitRate: 192, isConverted: true))
    }

    @Test func anMP3UnderTheCapIsStillTheOriginal() {
        network.isExpensive = true
        let small = Song(id: "so-2", title: "Small", bitRate: 128, suffix: "mp3")
        #expect(resolver().quality(for: small) == PlaybackQuality(format: "mp3", bitRate: 128))
    }

    @Test func aDownloadedOriginal() {
        downloads.files["so-1"] = URL(filePath: "/tmp/so-1.flac")
        network.isExpensive = true
        #expect(resolver().quality(for: flac) == PlaybackQuality(format: "flac", bitRate: 1411, isDownloaded: true))
    }

    @Test func aConvertedDownloadKnowsItsBitrate() {
        downloads.files["so-1"] = URL(filePath: "/tmp/so-1.mp3")
        downloads.convertedBitRates["so-1"] = 128
        #expect(resolver().quality(for: flac) == PlaybackQuality(format: "mp3", bitRate: 128, isConverted: true, isDownloaded: true))
    }

    @Test func anOlderConvertedDownloadIsStillMarkedConverted() {
        downloads.files["so-1"] = URL(filePath: "/tmp/so-1.mp3")
        #expect(resolver().quality(for: flac) == PlaybackQuality(format: "mp3", bitRate: nil, isConverted: true, isDownloaded: true))
    }
}

/// Builds stream URLs like `FakeStreamURLs`, and says each song's quality.
private struct QualityURLs: StreamURLProviding {
    func streamURL(for song: Song) throws -> URL {
        URL(string: "https://music.example.test/rest/stream?id=\(song.id)")!
    }

    func quality(for song: Song) -> PlaybackQuality? {
        PlaybackQuality(format: song.suffix, bitRate: song.bitRate)
    }
}

@MainActor
struct EngineQualityTests {
    private let player = FakeAudioPlayer()
    private let songs = [
        Song(id: "so-1", title: "One", duration: 200, bitRate: 1411, suffix: "flac"),
        Song(id: "so-2", title: "Two", duration: 200, bitRate: 320, suffix: "mp3"),
    ]

    private func makeEngine(store: InMemoryQueueStore = InMemoryQueueStore()) -> PlaybackEngine {
        PlaybackEngine(
            player: player, session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: QualityURLs(),
            store: store, scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
    }

    @Test func showsTheCurrentSongsQualityAndFollowsTheQueue() {
        let engine = makeEngine()
        engine.play(songs: songs)
        #expect(engine.currentQuality?.label == "FLAC · 1,411 kbps")
        player.finishCurrentItem()
        #expect(engine.currentQuality?.label == "MP3 · 320 kbps")
    }

    @Test func nothingBeforeASavedQueueIsLoaded() {
        let store = InMemoryQueueStore(QueueSnapshot(queue: PlaybackQueue(songs: songs), position: 30))
        let engine = makeEngine(store: store)
        #expect(engine.currentQuality == nil)
        engine.play()
        #expect(engine.currentQuality?.format == "FLAC")
    }

    @Test func aRadioStationHasNone() {
        let engine = makeEngine()
        let stream = URL(string: "https://radio.example.org/live")!
        engine.play(songs: [Song(station: RadioStation(id: "rs-1", name: "Live", streamURL: stream), stream: stream)])
        #expect(engine.currentQuality == nil)
    }
}
