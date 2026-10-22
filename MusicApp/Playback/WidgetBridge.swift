import NavidromeCore
import SwiftUI
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

    /// Shares the theme's colors with the widgets (and redraws them) when
    /// they've changed. A system accent is resolved for light and dark mode,
    /// as the widgets follow the phone's mode with it.
    static func shareTheme(_ settings: AppearanceSettings) {
        let theme: WidgetTheme
        if let palette = settings.theme.palette, let accent = settings.themeAccent {
            theme = WidgetTheme(palette: palette, accent: accent.color)
        } else {
            let color = UIColor(settings.systemAccent.color)
            theme = WidgetTheme(colors: nil, accentLight: hex(color, style: .light), accentDark: hex(color, style: .dark))
        }
        let store = WidgetSnapshotStore.shared()
        guard store.readTheme() != theme else { return }
        store.writeTheme(theme)
        reload()
    }

    private static func hex(_ color: UIColor, style: UIUserInterfaceStyle) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
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
