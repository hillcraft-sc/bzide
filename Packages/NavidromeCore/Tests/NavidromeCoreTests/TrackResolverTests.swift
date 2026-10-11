import Foundation
import Testing
@testable import NavidromeCore

@MainActor
final class FakeNetworkCost: NetworkCostMonitoring {
    var isExpensive = false
}

@MainActor
final class FakeDownloads: DownloadedTrackLookup {
    var files: [String: URL] = [:]

    func localFile(forSongID songID: String) -> URL? {
        files[songID]
    }
}

@MainActor
struct TrackResolverTests {
    private let song = Song(id: "so-1", title: "Dawn")
    private let network = FakeNetworkCost()
    private let downloads = FakeDownloads()
    private let settings = StreamingSettingsModel(defaults: UserDefaults(suiteName: "TrackResolverTests-\(UUID())")!)

    private func resolver() -> TrackResolver {
        TrackResolver(client: TestServer.client(FakeTransport()), settings: settings, network: network, downloads: downloads)
    }

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    @Test func wifiStreamsTheOriginalByDefault() throws {
        let url = try resolver().streamURL(for: song)
        #expect(url.path().hasSuffix("/rest/stream"))
        #expect(query(url)["id"] == "so-1")
        #expect(query(url)["maxBitRate"] == nil)
        #expect(query(url)["format"] == nil)
    }

    @Test func cellularUsesTheCellularQuality() throws {
        network.isExpensive = true
        let url = try resolver().streamURL(for: song)
        #expect(query(url)["maxBitRate"] == "192")
        #expect(query(url)["format"] == "mp3")
    }

    @Test func eachConnectionFollowsItsOwnSetting() throws {
        settings.settings = StreamingSettings(wifiQuality: .kbps320, cellularQuality: .original)
        let resolver = resolver()
        #expect(query(try resolver.streamURL(for: song))["maxBitRate"] == "320")

        network.isExpensive = true
        #expect(query(try resolver.streamURL(for: song))["maxBitRate"] == nil)
    }

    @Test func aDownloadedSongPlaysFromItsFile() throws {
        let file = URL(filePath: "/tmp/so-1.flac")
        downloads.files["so-1"] = file
        network.isExpensive = true
        #expect(try resolver().streamURL(for: song) == file)
    }
}

@MainActor
struct StreamingSettingsTests {
    @Test func settingsSurviveARestart() {
        let defaults = UserDefaults(suiteName: "StreamingSettingsTests-\(UUID())")!
        let first = StreamingSettingsModel(defaults: defaults)
        #expect(first.settings == StreamingSettings(wifiQuality: .original, cellularQuality: .kbps192))
        first.settings.cellularQuality = .kbps96

        let second = StreamingSettingsModel(defaults: defaults)
        #expect(second.settings.cellularQuality == .kbps96)
    }

    @Test func settingsSavedBeforeANewOneKeepTheirValues() {
        let defaults = UserDefaults(suiteName: "StreamingSettingsTests-\(UUID())")!
        defaults.set(Data("{\"wifiQuality\": 256, \"cellularQuality\": 96}".utf8), forKey: StreamingSettingsModel.key)
        let settings = StreamingSettingsModel(defaults: defaults).settings
        #expect(settings == StreamingSettings(wifiQuality: .kbps256, cellularQuality: .kbps96, downloadOverCellular: false))
    }

    @Test func unreadableSettingsFallBackToDefaults() {
        let defaults = UserDefaults(suiteName: "StreamingSettingsTests-\(UUID())")!
        defaults.set(Data("{\"wifiQuality\": 999}".utf8), forKey: StreamingSettingsModel.key)
        #expect(StreamingSettingsModel(defaults: defaults).settings == StreamingSettings())
    }
}
