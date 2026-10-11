import NavidromeCore
import os
import UIKit

/// The app's connections to iOS: audio output, the player, the lock screen,
/// the network, background downloads and device settings. Created once and kept
/// for the app's lifetime, across sign-outs: iOS allows one background download
/// session per identifier, and the lock screen's command handlers must be
/// registered once. Each signed-in account's engine takes these over.
final class SystemServices {
    let player = AVQueueAudioPlayer()
    let session = SystemAudioSession()
    let nowPlaying: SystemNowPlaying
    let network = SystemNetworkMonitor()
    let settings = StreamingSettingsModel()
    let downloadsDirectory: URL
    let downloadTransport: BackgroundDownloadTransport

    private static let logger = Logger(subsystem: "MusicApp", category: "SystemServices")

    init(loadArtwork: @escaping (String) async -> UIImage?) {
        nowPlaying = SystemNowPlaying(loadArtwork: loadArtwork)
        downloadsDirectory = Self.makeDownloadsDirectory()
        downloadTransport = BackgroundDownloadTransport(stagingDirectory: downloadsDirectory.appending(path: "Incoming"))
    }

    private static func makeDownloadsDirectory() -> URL {
        do {
            return try DownloadManager.applicationSupportDirectory()
        } catch {
            // Without a place to keep files, downloads can't persist; use temporary
            // storage so the rest of the app still works.
            logger.error("Downloads won't persist: \(String(describing: error), privacy: .public)")
            return URL.temporaryDirectory.appending(path: "Downloads")
        }
    }
}
