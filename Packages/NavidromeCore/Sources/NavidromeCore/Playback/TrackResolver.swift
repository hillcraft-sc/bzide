import Foundation

/// Finds downloaded copies of songs.
@MainActor
public protocol DownloadedTrackLookup: AnyObject {
    /// The local file for the song, if it's fully downloaded.
    func localFile(forSongID songID: String) -> URL?
}

/// Decides where the player gets each song: the downloaded file if there is one,
/// otherwise a stream at the quality the user chose for the current connection.
///
/// Asked whenever the engine loads a track, so a change of network or setting
/// applies from the next track loaded; a track already loaded keeps its quality.
@MainActor
public final class TrackResolver: StreamURLProviding {
    private let client: SubsonicClient
    private let settings: StreamingSettingsModel
    private let network: any NetworkCostMonitoring
    private let downloads: any DownloadedTrackLookup

    public init(
        client: SubsonicClient,
        settings: StreamingSettingsModel,
        network: any NetworkCostMonitoring,
        downloads: any DownloadedTrackLookup
    ) {
        self.client = client
        self.settings = settings
        self.network = network
        self.downloads = downloads
    }

    public func streamURL(for song: Song) throws -> URL {
        if let local = downloads.localFile(forSongID: song.id) {
            return local
        }
        let quality = network.isExpensive ? settings.settings.cellularQuality : settings.settings.wifiQuality
        let bitRate = quality.maxBitRate
        return try client.streamURL(songID: song.id, maxBitRate: bitRate, format: bitRate == nil ? nil : "mp3")
    }
}
