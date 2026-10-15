import AppIntents
import SwiftUI
import WidgetKit

/// "Favorite Song": hearts the song playing in Bzide, from the Lock Screen
/// (in place of the flashlight or camera) or Control Center. It always shows
/// the same heart, since the control can't know whether the song is a
/// favorite already; pressing it again keeps it a favorite.
struct FavoriteSongControl: ControlWidget {
    static let kind = "com.erichebert.musicapp.control.favoriteSong"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: FavoriteCurrentSongIntent()) {
                Label("Favorite Song", systemImage: "heart")
            }
        }
        .displayName("Favorite Song")
        .description("Adds the song playing in Bzide to your favorites.")
    }
}
