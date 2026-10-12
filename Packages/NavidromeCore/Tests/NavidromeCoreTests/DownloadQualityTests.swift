import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct DownloadQualityTests {
    private let root = URL.temporaryDirectory.appending(path: "DownloadQualityTests-\(UUID().uuidString)")
    private var directory: URL { root.appending(path: "Downloads") }

    /// The quality the next song starts with; tests change it between starts.
    private final class Setting {
        var quality: StreamQuality = .original
    }

    private func makeManager(_ transport: FakeDownloadTransport, setting: Setting) -> DownloadManager {
        DownloadManager(
            directory: directory,
            transport: transport,
            downloadURL: { URL(string: "https://music.example.test/rest/download?id=\($0)")! },
            convertedURL: { id, quality in
                URL(string: "https://music.example.test/rest/stream?id=\(id)&maxBitRate=\(quality.rawValue)&format=mp3")!
            },
            quality: { setting.quality },
            allowsCellular: { false }
        )
    }

    private func transport() -> FakeDownloadTransport {
        FakeDownloadTransport(scratch: root.appending(path: "scratch"))
    }

    private func album(_ count: Int) -> DownloadCollection {
        let songs = (1...count).map { Song(id: "so-\($0)", title: "Song \($0)", suffix: "flac") }
        return DownloadCollection(kind: .album, serverID: "al-1", name: "Album", songs: songs)
    }

    @Test func originalQualityDownloadsTheOriginalFile() throws {
        let transport = transport()
        let manager = makeManager(transport, setting: Setting())
        manager.download(album(1))
        #expect(transport.started.first?.url.path() == "/rest/download")
        transport.finish("so-1")
        #expect(try #require(manager.localFile(forSongID: "so-1")).pathExtension == "flac")
    }

    @Test func aLowerQualityDownloadsAConvertedMP3() throws {
        let transport = transport()
        let setting = Setting()
        setting.quality = .kbps192
        let manager = makeManager(transport, setting: setting)
        manager.download(album(1))
        let url = try #require(transport.started.first?.url)
        #expect(url.path() == "/rest/stream")
        #expect(url.queryParameters["maxBitRate"] == "192")
        #expect(url.queryParameters["format"] == "mp3")
        // Named for what it is, even though the original is FLAC.
        transport.finish("so-1", fileExtension: "flac")
        #expect(try #require(manager.localFile(forSongID: "so-1")).pathExtension == "mp3")
    }

    @Test func changingTheSettingMidwayKeepsEachSongsOwnFormat() throws {
        let transport = transport()
        let setting = Setting()
        setting.quality = .kbps128
        let manager = makeManager(transport, setting: setting)
        manager.download(album(4))
        // so-1…so-3 started converted; so-4 waits.
        setting.quality = .original
        transport.finish("so-1")
        // so-4 starts now, at original quality.
        #expect(transport.started.last?.songID == "so-4")
        #expect(transport.started.last?.url.path() == "/rest/download")
        transport.finish("so-2")
        transport.finish("so-4")
        #expect(try #require(manager.localFile(forSongID: "so-1")).pathExtension == "mp3")
        #expect(try #require(manager.localFile(forSongID: "so-2")).pathExtension == "mp3")
        #expect(try #require(manager.localFile(forSongID: "so-4")).pathExtension == "flac")
    }

    @Test func aConvertedDownloadFinishingAfterARelaunchIsStillNamedMP3() async throws {
        let setting = Setting()
        setting.quality = .kbps256
        let first = transport()
        makeManager(first, setting: setting).download(album(1))

        let second = transport()
        second.systemActive = ["so-1"]
        setting.quality = .original
        let relaunched = makeManager(second, setting: setting)
        await relaunched.resume()
        second.finish("so-1")
        #expect(try #require(relaunched.localFile(forSongID: "so-1")).pathExtension == "mp3")
    }

    @Test func anIndexSavedBeforeConversionStillLoads() throws {
        let old = #"{"collections":[],"files":{"so-1":{"fileName":"so-1.flac","bytes":10}}}"#
        let index = try JSONDecoder().decode(DownloadIndex.self, from: Data(old.utf8))
        #expect(index.files["so-1"]?.fileName == "so-1.flac")
        #expect(index.convertedFormats.isEmpty)
    }

    @Test func theSettingDefaultsToOriginalAndIsKept() throws {
        #expect(StreamingSettings().downloadQuality == .original)
        let saved = try JSONEncoder().encode(StreamingSettings(downloadQuality: .kbps96))
        #expect(try JSONDecoder().decode(StreamingSettings.self, from: saved).downloadQuality == .kbps96)
        // Settings saved before this existed keep their other values.
        let older = try JSONDecoder().decode(StreamingSettings.self, from: Data(#"{"wifiQuality":320}"#.utf8))
        #expect(older.downloadQuality == .original)
        #expect(older.wifiQuality == .kbps320)
    }
}
