import AVFoundation
import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct VolumeNormalizationTests {
    private let loud = ReplayGain(trackGain: -8, albumGain: -6.5, trackPeak: 0.99, albumPeak: 1.0)
    private let quiet = ReplayGain(trackGain: 6, albumGain: 4, trackPeak: 0.5, albumPeak: 0.8)

    @Test func offChangesNothing() {
        #expect(VolumeNormalization.off.decibels(for: loud) == nil)
        #expect(VolumeNormalization.off.gain(for: loud) == 1)
    }

    @Test func byTrackAndByAlbumUseTheirOwnGains() {
        #expect(VolumeNormalization.track.decibels(for: loud) == -8)
        #expect(VolumeNormalization.album.decibels(for: loud) == -6.5)
        #expect(abs(VolumeNormalization.track.gain(for: loud) - Float(pow(10, -8.0 / 20))) < 0.0001)
    }

    @Test func eachFallsBackToTheOtherGain() {
        let trackOnly = ReplayGain(trackGain: -3, trackPeak: 0.9)
        let albumOnly = ReplayGain(albumGain: -2, albumPeak: 0.9)
        #expect(VolumeNormalization.album.decibels(for: trackOnly) == -3)
        #expect(VolumeNormalization.track.decibels(for: albumOnly) == -2)
    }

    @Test func aBoostNeverClips() {
        // +6 dB would push a 0.5 peak to 1.0 exactly: allowed.
        #expect(abs((VolumeNormalization.track.decibels(for: quiet) ?? 0) - 6) < 0.05)
        // +4 dB on a 0.8 album peak would clip (0.8 × 1.58 > 1): capped at about +1.9 dB.
        let capped = VolumeNormalization.album.decibels(for: quiet) ?? 0
        #expect(abs(capped - (-20 * log10(0.8))) < 0.0001)
        #expect(Double(VolumeNormalization.album.gain(for: quiet)) * 0.8 <= 1.0001)
    }

    @Test func aSongWithoutReplayGainIsUnchanged() {
        #expect(VolumeNormalization.album.decibels(for: nil) == nil)
        #expect(VolumeNormalization.track.gain(for: ReplayGain()) == 1)
    }

    @Test func songsReadReplayGainFromTheServer() throws {
        let json = #"{"id":"so-1","title":"Loud","replayGain":{"trackGain":-8.2,"albumGain":"-6.5","trackPeak":0.99,"albumPeak":1}}"#
        let song = try JSONDecoder().decode(Song.self, from: Data(json.utf8))
        #expect(song.replayGain == ReplayGain(trackGain: -8.2, albumGain: -6.5, trackPeak: 0.99, albumPeak: 1))
        // Saved with the queue and read back the same.
        let saved = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(song))
        #expect(saved.replayGain == song.replayGain)
        // No gains at all, or none sent: no ReplayGain.
        let empty = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"so-2","title":"A","replayGain":{"trackPeak":0.9}}"#.utf8))
        #expect(empty.replayGain == nil)
        let none = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"so-3","title":"B"}"#.utf8))
        #expect(none.replayGain == nil)
    }

    @Test func theQualityLineShowsTheAdjustment() {
        var quality = PlaybackQuality(format: "flac", bitRate: 900)
        quality.normalization = -4.24
        #expect(quality.label == "FLAC · 900 kbps · \u{2212}4.2 dB")
        quality.normalization = 1.5
        #expect(quality.label.hasSuffix("+1.5 dB"))
        quality.normalization = 0.01
        #expect(quality.label.hasSuffix("· 0 dB"))
    }

    @Test func normalizationIsOffByDefault() throws {
        #expect(StreamingSettings().volumeNormalization == .off)
        let older = try JSONDecoder().decode(StreamingSettings.self, from: Data(#"{"wifiQuality":0,"cellularQuality":192}"#.utf8))
        #expect(older.volumeNormalization == .off)
        let saved = try JSONDecoder().decode(StreamingSettings.self, from: JSONEncoder().encode(StreamingSettings(volumeNormalization: .album)))
        #expect(saved.volumeNormalization == .album)
    }

    @Test func theTapScalesTheSamples() {
        var samples: [Float] = [0.5, -0.25, 1, 0]
        samples.withUnsafeMutableBufferPointer { pointer in
            let list = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(list.unsafeMutablePointer) }
            list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(pointer.count * MemoryLayout<Float>.size), mData: pointer.baseAddress)
            AudioLevelMeter.apply(0.5, to: list)
        }
        #expect(samples == [0.25, -0.125, 0.5, 0])
    }

    @Test func aTapGainCanChangeWhilePlaying() {
        let gain = TapGain(0.5)
        #expect(gain.value == 0.5)
        gain.value = 1.25
        #expect(gain.value == 1.25)
    }

    @Test func theEngineLoadsEachSongWithItsGainAndUpdatesThem() {
        let player = FakeAudioPlayer()
        var urls = FakeStreamURLs()
        urls.gains = ["so-1": 0.5, "so-2": 1.5]
        let engine = PlaybackEngine(
            player: player, session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: urls, store: InMemoryQueueStore(),
            scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
        engine.play(songs: [Song(id: "so-1", title: "One"), Song(id: "so-2", title: "Two"), Song(id: "so-3", title: "Three")])
        #expect(player.loaded.map(\.gain) == [0.5, 1.5])
        engine.refreshGains()
        let current = engine.queue.entries[0].id
        let next = engine.queue.entries[1].id
        #expect(player.gains[current] == 0.5)
        #expect(player.gains[next] == 1.5)
    }
}
