import AppIntents
import NavidromeCore
import SwiftUI
import WidgetKit

/// "Favorite Song": hearts the song playing in Bzide, from the Lock Screen
/// (in place of the flashlight or camera) or Control Center. The heart is
/// filled when the playing song is a favorite already (from what the app
/// shares; see `WidgetSnapshot`). Pressing it always favorites, so a second
/// press can't undo it.
struct FavoriteSongControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKinds.favoriteControl, provider: FavoriteValueProvider()) { isFavorite in
            ControlWidgetButton(action: FavoriteCurrentSongIntent()) {
                Label("Favorite Song", systemImage: isFavorite ? "heart.fill" : "heart")
            }
        }
        .displayName("Favorite Song")
        .description("Adds the song playing in Bzide to your favorites.")
    }
}

/// Whether the playing song is a favorite; `false` with nothing playing or a station.
struct FavoriteValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        WidgetSnapshotStore.shared().read()?.isFavorite ?? false
    }
}
