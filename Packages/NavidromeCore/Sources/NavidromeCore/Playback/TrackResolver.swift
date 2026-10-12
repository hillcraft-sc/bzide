import Foundation

/// Finds downloaded copies of songs.
@MainActor
public protocol DownloadedTrackLookup: AnyObject {
    /// The local file for the song, if it's fully downloaded.
    func localFile(forSongID songID: String) -> URL?
    /// The bitrate a downloaded song was converted to; `nil` for an original
    /// (or a conversion from before this was recorded).
    func convertedBitRate(forSongID songID: String) -> Int?
}

extension DownloadedTrackLookup {
    public func convertedBitRate(forSongID songID: String) -> Int? { nil }
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
        let bitRate = streamingCap
        return try client.streamURL(songID: song.id, maxBitRate: bitRate, format: bitRate == nil ? nil : "mp3")
    }

    /// Decided the same way as `streamURL(for:)`, so it describes the same choice.
    public func quality(for song: Song) -> PlaybackQuality? {
        guard let local = downloads.localFile(forSongID: song.id) else {
            return .streamed(song, cap: streamingCap)
        }
        if let bitRate = downloads.convertedBitRate(forSongID: song.id) {
            return PlaybackQuality(format: DownloadManager.convertedFormat, bitRate: bitRate, isConverted: true, isDownloaded: true)
        }
        // A converted download from before its bitrate was recorded: MP3 in place of another format.
        let fileFormat = local.pathExtension.lowercased()
        if fileFormat == DownloadManager.convertedFormat, song.suffix?.lowercased() != fileFormat {
            return PlaybackQuality(format: fileFormat, bitRate: nil, isConverted: true, isDownloaded: true)
        }
        return .original(song, downloaded: true)
    }

    private var streamingCap: Int? {
        (network.isExpensive ? settings.settings.cellularQuality : settings.settings.wifiQuality).maxBitRate
    }
}
