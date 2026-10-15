import AppIntents

/// The extension's side of the favorite intents. They're audio playback
/// intents, which the system runs in the app, where the music is; this only
/// runs if the system runs one here instead (the app isn't running, so
/// nothing is playing), and says so.
enum CurrentSongFavorite {
    @MainActor
    static func set(_ favorite: Bool) async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Play something in Bzide first.")
    }
}
