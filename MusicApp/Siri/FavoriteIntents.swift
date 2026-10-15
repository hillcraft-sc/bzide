import AppIntents
import NavidromeCore

// "Favorite this song in Bzide": the app's side of the favorite intents
// (defined in FavoriteIntentDefinitions.swift, shared with the controls
// extension). Hearts the song playing now, as Now Playing's heart does.

@MainActor
enum CurrentSongFavorite {
    static func set(_ favorite: Bool) async throws -> some IntentResult & ProvidesDialog {
        let library = try SiriAccess.library()
        let song: Song
        switch await library.setCurrentSongFavorite(favorite) {
        case .done(let favorited): song = favorited
        case .nothingPlaying: throw SiriError.nothingPlaying
        case .radio: throw SiriError.radio
        case .failed(let message):
            // Siri says it; no need for the app's alert as well.
            library.stars.dismissError()
            throw SiriError.server(message)
        }
        let dialog: IntentDialog = favorite
            ? IntentDialog(full: "Added \u{201C}\(song.title)\u{201D} to your favorites.", supporting: "Favorited")
            : IntentDialog(full: "Removed \u{201C}\(song.title)\u{201D} from your favorites.", supporting: "Unfavorited")
        return .result(dialog: dialog)
    }
}

/// What can be said to Siri without setting anything up. Phrases must name
/// the app; the intents also appear in Shortcuts and for the Action button.
struct BzideShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FavoriteCurrentSongIntent(),
            phrases: [
                "Favorite this song in \(.applicationName)",
                "Favorite this in \(.applicationName)",
                "Add this song to my favorites in \(.applicationName)",
            ],
            shortTitle: "Favorite Song",
            systemImageName: "heart"
        )
        AppShortcut(
            intent: UnfavoriteCurrentSongIntent(),
            phrases: [
                "Unfavorite this song in \(.applicationName)",
                "Remove this song from my favorites in \(.applicationName)",
            ],
            shortTitle: "Unfavorite Song",
            systemImageName: "heart.slash"
        )
    }
}
