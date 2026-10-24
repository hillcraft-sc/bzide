import AppIntents
import NavidromeCore

// "Play this", "shuffle Radiohead in Bzide", "play this next", "add this to
// my running playlist". They do what the long-press menus do, through the
// same models, so the rules match: artists oldest album first, playlists
// skip songs already in them.

@AppIntent(schema: .audio.playAudio)
struct PlayAudioIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play"
    static let description = IntentDescription("Plays a song, album, artist or playlist from your Navidrome library.")

    var audioEntity: PlayableEntity
    @Parameter(default: [])
    var playbackAttributes: Set<PlaybackAttributes>
    var queueLocation: QueueInsertionLocation?
    var warmupAudioQueueResult: WarmupAudioQueueResult?

    @MainActor
    func perform() async throws -> some IntentResult {
        let library = try SiriAccess.library()
        let engine = library.engine
        if case .playlist(let playlist) = audioEntity, playlist.id == PlaylistEntity.randomMixID {
            await library.randomMix.start()
            return .result()
        }
        // "Play music in Bzide" names the current song: carry on with the
        // queue rather than replacing it with that one song.
        if case .song(let song) = audioEntity, song.id == engine.queue.current?.song.id,
           queueLocation == nil, playbackAttributes.isEmpty {
            engine.play()
            return .result()
        }
        let songs = try await SiriSongs.resolve(audioEntity, in: library, confirmingWith: self)
        switch queueLocation {
        case .next: engine.playNext(songs)
        case .tail: engine.append(songs)
        case nil:
            if playbackAttributes.contains(.shuffle) {
                engine.playShuffled(songs)
            } else {
                engine.play(songs: songs)
            }
            if playbackAttributes.contains(.repeat) {
                engine.setRepeatMode(.all)
            }
        }
        return .result()
    }
}

/// "Play music in Bzide", "Play Bzide": carries on with the queue, or starts
/// a Random Mix when nothing is queued. An App Shortcut phrase (see
/// `BzideShortcuts`), because Siri doesn't send these to the audio search:
/// without a phrase it answered that Bzide doesn't support that (Gitea #34).
struct PlayMusicIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Music"
    static let description = IntentDescription("Carries on with what you were listening to in Bzide, or starts a Random Mix.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let library = try SiriAccess.library()
        if library.engine.queue.current != nil {
            library.engine.play()
        } else {
            // Awaited, so the system keeps the app running until the music starts.
            await library.randomMix.start()
        }
        return .result()
    }
}

@AppIntent(schema: .audio.addToPlaylist)
struct AddToPlaylistIntent {
    static let title: LocalizedStringResource = "Add to Playlist"

    var audioEntity: PlayableEntity
    var playlist: PlaylistEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let library = try SiriAccess.library()
        let songs = try await SiriSongs.resolve(audioEntity, in: library, confirmingWith: self)
        let editor = library.playlistEditor
        let target = Playlist(id: playlist.id, name: playlist.title)
        guard await editor.add(songs, to: target) else {
            let message = editor.error ?? "Couldn't add to \(playlist.title)."
            editor.dismissError()
            throw SiriError.server(message)
        }
        let message = editor.confirmation ?? "Added to \(playlist.title)."
        // Said by Siri; no need for the banner as well.
        editor.dismissConfirmation()
        return .result(dialog: IntentDialog(full: "\(message)", supporting: "Added"))
    }
}

/// Turns what Siri named into songs, asking first for a big artist, as the
/// app's menus do.
@MainActor
enum SiriSongs {
    static func resolve(_ entity: PlayableEntity, in library: Library, confirmingWith intent: some AppIntent) async throws -> [Song] {
        let quick = library.quickActions
        // Random Mix isn't songs to add; it's started by playing it.
        if case .playlist(let playlist) = entity, playlist.id == PlaylistEntity.randomMixID {
            throw SiriError.notFound
        }
        do {
            if case .artist(let artist) = entity {
                let (_, count) = try await quick.songCount(ofArtist: artist.id)
                if count > QuickActions.confirmationThreshold {
                    try await intent.requestConfirmation(dialog: "That's \(count) songs by \(artist.name). Go ahead?")
                }
            }
            let songs = try await quick.resolve(entity.source).songs
            guard !songs.isEmpty else { throw SiriError.notFound }
            return songs
        } catch let error as SubsonicError {
            throw SiriError.server(error.localizedDescription)
        }
    }
}

// MARK: - Schema enums and results

@AppEnum(schema: .audio.playbackAttributes)
enum PlaybackAttributes: String {
    case shuffle
    case `repeat`

    static let caseDisplayRepresentations: [PlaybackAttributes: DisplayRepresentation] = [
        .shuffle: "Shuffle",
        .repeat: "Repeat",
    ]
}

@AppEnum(schema: .audio.queueInsertionLocation)
enum QueueInsertionLocation: String {
    case next
    case tail

    static let caseDisplayRepresentations: [QueueInsertionLocation: DisplayRepresentation] = [
        .next: "Next",
        .tail: "Last",
    ]
}

/// Required by the play schema. Bzide doesn't prepare a queue ahead of time.
@AppEntity(schema: .audio.warmupAudioQueueResult)
struct WarmupAudioQueueResult: TransientAppEntity {
    var displayRepresentation: DisplayRepresentation {
        "Warmup Audio Queue Result"
    }

    init() {}
}
