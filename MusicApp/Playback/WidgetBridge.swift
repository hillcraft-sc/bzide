import NavidromeCore
import UIKit
import WidgetKit

/// Connects `WidgetFeed` to the app's artwork and to WidgetKit: the Now
/// Playing and Shortcuts widgets and the Favorite Song control read what it writes.
@MainActor
enum WidgetBridge {
    /// Big enough for the medium widget's cover on any iPhone, small enough
    /// for WidgetKit's image limits.
    static let artworkPixels = 400

    static func makeFeed(engine: PlaybackEngine, stars: StarModel, artwork: ArtworkCache) -> WidgetFeed {
        let feed = WidgetFeed(
            engine: engine, stars: stars, store: .shared(),
            artwork: { cover in
                guard let image = await artwork.image(for: cover, pixels: artworkPixels) else { return nil }
                return jpeg(image)
            },
            reload: reload
        )
        observeTermination(of: feed)
        return feed
    }

    /// Posted on the main thread; the handler is built nonisolated, as
    /// NotificationCenter's closures aren't main-actor isolated.
    nonisolated private static func observeTermination(of feed: WidgetFeed) {
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak feed] _ in
            MainActor.assumeIsolated { feed?.appWillTerminate() }
        }
    }

    /// After signing out: the widgets show nothing playing, not the last account's song.
    static func clear() {
        let store = WidgetSnapshotStore.shared()
        store.write(nil)
        store.writeArtwork(nil)
        reload()
    }

    private static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.nowPlaying)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.shortcuts)
        ControlCenter.shared.reloadControls(ofKind: WidgetKinds.favoriteControl)
    }

    /// Scaled down if the server sent it bigger than asked.
    private static func jpeg(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > CGFloat(artworkPixels) else { return image.jpegData(compressionQuality: 0.8) }
        let scale = CGFloat(artworkPixels) / longest
        let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.8)
    }
}
