import AppIntents

// Shared by the app and the BzideControls extension (the lock screen and
// Control Center button), so the system knows the intents in both. They're
// audio playback intents, so the system runs them in the app's process,
// where the queue and the server connection are; each target has its own
// `CurrentSongFavorite`, and the extension's only asks to open the app, for
// the rare case they're run there.
//
// "Favorite this song in Bzide" hearts the song playing now, as Now
// Playing's heart does. It sets rather than flips, so a second press (from
// the Action button, a Shortcut, or the lock screen control) can't undo it.
// Unfavorite is its own intent.

struct FavoriteCurrentSongIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Favorite Current Song"
    static let description = IntentDescription("Adds the song playing in Bzide to your favorites on your Navidrome server.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await CurrentSongFavorite.set(true)
    }
}

struct UnfavoriteCurrentSongIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Unfavorite Current Song"
    static let description = IntentDescription("Removes the song playing in Bzide from your favorites on your Navidrome server.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await CurrentSongFavorite.set(false)
    }
}
