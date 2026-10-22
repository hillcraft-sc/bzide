import AppIntents
import Foundation

// The widgets' buttons (Now Playing and Shortcuts). Shared by the app and the BzideControls
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
        await WidgetPlayback.perform(.togglePlayPause)
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Skips to the next song in Bzide.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await WidgetPlayback.perform(.next)
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let description = IntentDescription("Goes back a song in Bzide, or to the start of this one.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await WidgetPlayback.perform(.previous)
        return .result()
    }
}

struct ContinuePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Continue"
    static let description = IntentDescription("Plays Bzide's queue from where it left off.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await WidgetPlayback.perform(.resume)
        return .result()
    }
}

struct RandomMixIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Random Mix"
    static let description = IntentDescription("Plays random songs from your library in Bzide.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await WidgetPlayback.perform(.randomMix)
        return .result()
    }
}

struct MixMyCutsIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Mix My Cuts"
    static let description = IntentDescription("Plays a mix of your rated and favorite songs in Bzide.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await WidgetPlayback.perform(.myCuts)
        return .result()
    }
}

/// What a widget button asks for.
enum WidgetCommand {
    case togglePlayPause, next, previous, resume, randomMix, myCuts
}

/// The widgets' and controls' kinds, which the app needs to reload them.
enum WidgetKinds {
    static let nowPlaying = "com.erichebert.musicapp.widget.nowPlaying"
    static let favoriteControl = "com.erichebert.musicapp.control.favoriteSong"
    static let shortcuts = "com.erichebert.musicapp.widget.shortcuts"
}

/// Where tapping a widget goes (the app registers the `bzide` scheme).
enum WidgetLinks {
    static let nowPlaying = URL(string: "bzide://now-playing")
}
