import AppIntents
import Foundation

// The Now Playing widget's buttons. Shared by the app and the BzideControls
// extension, like the favorite intents (see FavoriteIntentDefinitions.swift):
// they're audio playback intents, so the system runs them in the app's
// process, starting it in the background if need be; each target has its
// own `WidgetPlayback`, and the extension's does nothing, for the rare case
// one is run there.

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses Bzide.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetPlayback.perform(.togglePlayPause)
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Skips to the next song in Bzide.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetPlayback.perform(.next)
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let description = IntentDescription("Goes back a song in Bzide, or to the start of this one.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetPlayback.perform(.previous)
        return .result()
    }
}

/// What a widget button asks for.
enum WidgetCommand {
    case togglePlayPause, next, previous
}

/// The widgets' and controls' kinds, which the app needs to reload them.
enum WidgetKinds {
    static let nowPlaying = "com.erichebert.musicapp.widget.nowPlaying"
    static let favoriteControl = "com.erichebert.musicapp.control.favoriteSong"
}

/// Where tapping a widget goes (the app registers the `bzide` scheme).
enum WidgetLinks {
    static let nowPlaying = URL(string: "bzide://now-playing")
}
