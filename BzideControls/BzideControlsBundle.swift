import SwiftUI
import WidgetKit

/// Bzide's controls for the Lock Screen and Control Center. A control can't
/// see what's playing (that needs an App Group the free developer account
/// doesn't have), so they're plain buttons whose intents run in the app.
@main
struct BzideControlsBundle: WidgetBundle {
    var body: some Widget {
        FavoriteSongControl()
    }
}
