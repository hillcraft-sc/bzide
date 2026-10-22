import SwiftUI
import WidgetKit

/// Bzide's widgets and controls. They can't see the engine, which lives in
/// the app: they read what the app shares in the App Group (`WidgetSnapshot`),
/// and their buttons are audio playback intents, which run in the app.
@main
struct BzideControlsBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        FavoriteSongControl()
    }
}
