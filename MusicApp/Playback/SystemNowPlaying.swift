import MediaPlayer
import NavidromeCore
import UIKit

/// Connects the engine to the lock screen, Control Center, headphone buttons and
/// CarPlay through `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.
///
/// Lives in the app target because artwork needs `UIImage`. Lives for the app's lifetime.
final class SystemNowPlaying: NowPlayingControlling {
    var onCommand: (@MainActor (RemoteCommand) -> Void)?

    /// Fetches cover art by id. Supplied by the app so this type never builds
    /// authenticated URLs itself.
    private let loadArtwork: (String) async -> UIImage?
    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var artworkCoverID: String?
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?

    init(loadArtwork: @escaping (String) async -> UIImage?) {
        self.loadArtwork = loadArtwork
        registerCommands()
    }

    func update(_ info: NowPlayingInfo?) {
        guard let info else {
            infoCenter.nowPlayingInfo = nil
            artworkTask?.cancel()
            artworkCoverID = nil
            artwork = nil
            return
        }
        commandCenter.nextTrackCommand.isEnabled = info.hasNext
        // Previous always works for songs: it restarts the track when there's
        // nothing before it. A station can't be restarted or scrubbed.
        commandCenter.previousTrackCommand.isEnabled = !info.isLiveStream
        commandCenter.changePlaybackPositionCommand.isEnabled = !info.isLiveStream

        var dictionary: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        dictionary[MPMediaItemPropertyArtist] = info.artist
        dictionary[MPMediaItemPropertyAlbumTitle] = info.album
        dictionary[MPMediaItemPropertyPlaybackDuration] = info.duration
        dictionary[MPNowPlayingInfoPropertyIsLiveStream] = info.isLiveStream
        if info.coverArtID == artworkCoverID {
            dictionary[MPMediaItemPropertyArtwork] = artwork
        } else {
            fetchArtwork(for: info.coverArtID)
        }
        infoCenter.nowPlayingInfo = dictionary
    }

    // MARK: - Artwork

    private func fetchArtwork(for coverID: String?) {
        artworkTask?.cancel()
        artworkCoverID = coverID
        artwork = nil
        guard let coverID else { return }
        artworkTask = Task { [weak self, loadArtwork] in
            guard let image = await loadArtwork(coverID), !Task.isCancelled else { return }
            self?.artworkLoaded(image, for: coverID)
        }
    }

    private func artworkLoaded(_ image: UIImage, for coverID: String) {
        // The track may have changed while the image was loading.
        guard coverID == artworkCoverID, var dictionary = infoCenter.nowPlayingInfo else { return }
        let artwork = Self.makeArtwork(image)
        self.artwork = artwork
        dictionary[MPMediaItemPropertyArtwork] = artwork
        infoCenter.nowPlayingInfo = dictionary
    }

    /// MediaPlayer calls the artwork closure on its own background queue. This app
    /// target defaults to main-actor isolation, so a closure written in a method
    /// here would be main-actor isolated and trap (or hang) when called off the
    /// main thread. Building it in a nonisolated function keeps it callable anywhere.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: - Commands

    private func registerCommands() {
        register(commandCenter.playCommand) { _ in .play }
        register(commandCenter.pauseCommand) { _ in .pause }
        register(commandCenter.togglePlayPauseCommand) { _ in .togglePlayPause }
        register(commandCenter.nextTrackCommand) { _ in .next }
        register(commandCenter.previousTrackCommand) { _ in .previous }
        register(commandCenter.changePlaybackPositionCommand) { event in
            (event as? MPChangePlaybackPositionCommandEvent).map { .seek(to: $0.positionTime) }
        }
        // No like or dislike: iOS draws liking as a star on the lock screen,
        // which in Bzide means rating, not favoriting (Gitea #14). Favorites
        // are Now Playing's heart, the widgets, the Favorite Song control and
        // "Favorite this song in Bzide".
        commandCenter.likeCommand.isEnabled = false
        commandCenter.dislikeCommand.isEnabled = false
    }

    private func register(_ command: MPRemoteCommand, _ makeCommand: @escaping @Sendable (MPRemoteCommandEvent) -> RemoteCommand?) {
        command.isEnabled = true
        command.addTarget(handler: Self.handler(for: self, makeCommand))
    }

    /// Remote command handlers are documented to run on the main thread, but the
    /// handler is built nonisolated (see `makeArtwork`) so that if one ever doesn't,
    /// it fails at `assumeIsolated` with a clear message rather than a hidden check.
    nonisolated private static func handler(
        for target: SystemNowPlaying,
        _ makeCommand: @escaping @Sendable (MPRemoteCommandEvent) -> RemoteCommand?
    ) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { [weak target] event in
            // Read the event here; only the resulting value crosses to the main actor.
            guard let remoteCommand = makeCommand(event) else { return .commandFailed }
            return MainActor.assumeIsolated {
                guard let target, let onCommand = target.onCommand else { return .commandFailed }
                onCommand(remoteCommand)
                return .success
            }
        }
    }
}
