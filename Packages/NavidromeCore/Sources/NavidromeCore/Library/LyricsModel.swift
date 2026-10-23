import Foundation
import Observation

/// Finds the current song's lyrics for the Lyrics screen, trying in order:
///
/// 1. The server's synced lyrics.
/// 2. LRCLIB's synced lyrics, if the user allows looking online.
/// 3. The server's plain lyrics.
/// 4. LRCLIB's plain lyrics, if allowed.
///
/// So synced lyrics win wherever they come from, and the server wins between
/// equals. Results are kept for the session, so reopening is instant. When
/// nothing is found, a note says why, so a gap can be told from a bad match.
///
/// LRCLIB's lyrics are sometimes for another recording of the song. "Wrong
/// lyrics?" (`tryAnother`) moves to LRCLIB's next match, or turns LRCLIB off
/// for the song; the choice is remembered (`LyricsChoices`). The server's
/// own lyrics are never changed.
@MainActor
@Observable
public final class LyricsModel {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded(Lyrics)
        /// LRCLIB knows the song has no words.
        case instrumental
        /// Nothing found; `note` says why (online lookup off, LRCLIB had
        /// nothing, or only a version that didn't fit).
        case none(note: String?)
        /// Radio streams have no lyrics to look up.
        case radio
        case failed(String)
    }

    /// What the server and LRCLIB have for a song. `nil` means none.
    public struct Sources: Sendable {
        public var server: @Sendable (Song) async throws -> Lyrics?
        /// LRCLIB's best match.
        public var online: @Sendable (Song) async throws -> OnlineLyrics?
        /// One LRCLIB entry by its id; `nil` if it's gone.
        public var onlineEntry: @Sendable (Song, Int) async throws -> Lyrics?
        /// Every LRCLIB entry that fits the song, best first.
        public var onlineMatches: @Sendable (Song) async throws -> [Lyrics]

        public init(
            server: @escaping @Sendable (Song) async throws -> Lyrics?,
            online: @escaping @Sendable (Song) async throws -> OnlineLyrics?,
            onlineEntry: @escaping @Sendable (Song, Int) async throws -> Lyrics? = { _, _ in nil },
            onlineMatches: @escaping @Sendable (Song) async throws -> [Lyrics] = { _ in [] }
        ) {
            self.server = server
            self.online = online
            self.onlineEntry = onlineEntry
            self.onlineMatches = onlineMatches
        }
    }

    /// What "Wrong lyrics?" did.
    public enum Another: Equatable, Sendable {
        /// The next match is showing.
        case shown
        /// LRCLIB has no other match.
        case noMore
        /// LRCLIB couldn't be reached.
        case failed
    }

    public enum OnlineLyrics: Sendable, Equatable {
        case lyrics(Lyrics)
        case instrumental
        /// Nothing usable: the closest candidate turned down, or `nil` if
        /// there were none.
        case notFound(LyricsMatching.Rejection?)
    }

    /// The note when lyrics could be found online but the user hasn't allowed it.
    public static let onlineOffNote = "Turning on Find Lyrics Online in Settings > Lyrics would also search LRCLIB."
    /// The note when LRCLIB couldn't be reached but the server answered.
    public static let onlineFailedNote = "LRCLIB couldn't be reached to look further."
    /// The note when the user turned LRCLIB off for the song.
    public static let onlineTurnedDownNote = "You chose not to use LRCLIB's lyrics for this song."

    public private(set) var state: State = .idle
    /// Whether "Wrong lyrics?" is looking for the next match.
    public private(set) var isTryingAnother = false
    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private let choices: LyricsChoices
    /// The last song and settings loaded, for `tryAnother` and reloading.
    @ObservationIgnored private var current: (song: Song, onlineAllowed: Bool, usesChoices: Bool)?
    @ObservationIgnored private var cache: [String: State] = [:]
    /// Bumped by each load; only the latest load's answer is shown.
    @ObservationIgnored private var generation = 0

    public init(sources: Sources, choices: LyricsChoices = LyricsChoices()) {
        self.sources = sources
        self.choices = choices
    }

    /// The user's LRCLIB choice for the song, if any.
    public func choice(for song: Song) -> LyricsChoices.Choice? {
        choices.choice(for: song.id)
    }

    /// Loads lyrics for `song` unless they're already known. A newer request
    /// always wins: a slow answer for an earlier song is dropped. A canceled
    /// load (the screen closed mid-search) shows and keeps nothing, so the
    /// next one starts afresh.
    /// `usesChoices`: whether the user's "Wrong lyrics?" choices apply (the
    /// Wrong Lyrics Button setting); without, LRCLIB's best match.
    public func load(_ song: Song?, onlineAllowed: Bool, usesChoices: Bool = true) async {
        generation += 1
        let mine = generation
        guard let song else {
            state = .none(note: nil)
            return
        }
        guard !song.isLive else {
            state = .radio
            return
        }
        current = (song, onlineAllowed, usesChoices)
        let key = cacheKey(song, onlineAllowed: onlineAllowed, usesChoices: usesChoices)
        if let cached = cache[key] {
            state = cached
            return
        }
        state = .loading
        let found = await find(song, onlineAllowed: onlineAllowed, choice: usesChoices ? choices.choice(for: song.id) : nil)
        // Another load started meanwhile, or this one was canceled.
        guard mine == generation, !Task.isCancelled, let found else { return }
        // A failure is tried again next time, so a brief outage isn't kept.
        if found.isComplete { cache[key] = found.state }
        state = found.state
    }

    /// The choice is part of the key, so changing it looks again.
    private func cacheKey(_ song: Song, onlineAllowed: Bool, usesChoices: Bool) -> String {
        let choice = switch usesChoices ? choices.choice(for: song.id) : nil {
        case .lrclib(let id): "lrclib:\(id)"
        case .turnedDown?: "turnedDown"
        case nil: "best"
        }
        return "\(song.id)|\(onlineAllowed)|\(choice)"
    }

    // MARK: - Wrong lyrics?

    /// Shows LRCLIB's next match for the song and remembers it. Only for
    /// lyrics from LRCLIB that are showing now.
    public func tryAnother() async -> Another {
        guard let current, current.usesChoices, case .loaded(let shown) = state, shown.source == .lrclib, !isTryingAnother else { return .noMore }
        isTryingAnother = true
        defer { isTryingAnother = false }
        let matches: [Lyrics]
        do {
            matches = try await sources.onlineMatches(current.song)
        } catch {
            return .failed
        }
        // The one after what's showing (the first if what's showing isn't
        // among them), and never the same words again.
        let index = matches.firstIndex { $0.lrclibID != nil && $0.lrclibID == shown.lrclibID }
        let shownWords = shown.lines.map(\.text)
        let next = matches.dropFirst(index.map { $0 + 1 } ?? 0).first {
            $0.lrclibID != shown.lrclibID && $0.lines.map(\.text) != shownWords
        }
        guard let next, let id = next.lrclibID else { return .noMore }
        choices.set(.lrclib(id: id), for: current.song.id)
        // The screen may have moved on to another song meanwhile.
        guard self.current?.song.id == current.song.id else { return .shown }
        state = .loaded(next)
        cache[cacheKey(current.song, onlineAllowed: current.onlineAllowed, usesChoices: true)] = state
        return .shown
    }

    /// Turns LRCLIB off for the song: the server's lyrics, or none.
    public func turnDownOnline() async {
        guard let current else { return }
        choices.set(.turnedDown, for: current.song.id)
        await load(current.song, onlineAllowed: current.onlineAllowed, usesChoices: current.usesChoices)
    }

    /// Forgets the choice: LRCLIB's best match again.
    public func useBestMatch() async {
        guard let current else { return }
        choices.set(nil, for: current.song.id)
        await load(current.song, onlineAllowed: current.onlineAllowed, usesChoices: current.usesChoices)
    }

    /// An answer, and whether every source answered (so it can be kept).
    private struct Found {
        var state: State
        var isComplete: Bool
    }

    /// `nil` if a lookup was canceled.
    private func find(_ song: Song, onlineAllowed: Bool, choice: LyricsChoices.Choice?) async -> Found? {
        var serverFailed = false
        var server: Lyrics?
        do {
            server = try await sources.server(song)
        } catch {
            if Self.isCancellation(error) { return nil }
            serverFailed = true
        }
        if let server, server.isSynced { return Found(state: .loaded(server), isComplete: true) }

        var onlineFailed = false
        var online: OnlineLyrics?
        if onlineAllowed, choice != .turnedDown {
            do {
                online = try await onlineLyrics(song, choice: choice)
            } catch {
                if Self.isCancellation(error) { return nil }
                onlineFailed = true
            }
        }
        let isComplete = !serverFailed && !onlineFailed
        if case .lyrics(let lyrics) = online, lyrics.isSynced { return Found(state: .loaded(lyrics), isComplete: true) }
        if let server { return Found(state: .loaded(server), isComplete: isComplete) }
        if case .lyrics(let lyrics) = online { return Found(state: .loaded(lyrics), isComplete: isComplete) }
        if case .instrumental = online { return Found(state: .instrumental, isComplete: isComplete) }
        // Nothing found: say so, unless nothing could be asked.
        let couldAsk = !serverFailed || (onlineAllowed && !onlineFailed)
        guard couldAsk else { return Found(state: .failed("Couldn't load lyrics. Check your connection and try again."), isComplete: false) }
        let note = choice == .turnedDown && onlineAllowed
            ? Self.onlineTurnedDownNote
            : Self.note(onlineAllowed: onlineAllowed, onlineFailed: onlineFailed, online: online)
        return Found(state: .none(note: note), isComplete: isComplete)
    }

    /// The chosen entry, or the best match if there's no choice, the chosen
    /// one is gone from LRCLIB, or it can't be found just now.
    private func onlineLyrics(_ song: Song, choice: LyricsChoices.Choice?) async throws -> OnlineLyrics? {
        if case .lrclib(let id) = choice {
            do {
                if let chosen = try await sources.onlineEntry(song, id) { return .lyrics(chosen) }
            } catch {
                if Self.isCancellation(error) { throw error }
            }
        }
        return try await sources.online(song)
    }

    /// A canceled request isn't a failure: nobody is waiting for the answer.
    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// Why nothing was found online, for the No Lyrics message.
    private static func note(onlineAllowed: Bool, onlineFailed: Bool, online: OnlineLyrics?) -> String {
        guard onlineAllowed else { return onlineOffNote }
        guard !onlineFailed else { return onlineFailedNote }
        if case .notFound(let rejection) = online { return LyricsMatching.explain(rejection) }
        return LyricsMatching.explain(nil)
    }
}

extension LyricsModel.Sources {
    /// The real server and LRCLIB. The server is asked for synced lyrics only
    /// if it advertises the OpenSubsonic `songLyrics` extension (checked once);
    /// otherwise, or if it has none, for plain lyrics.
    public static func live(client: SubsonicClient, lrclib: LRCLIBClient) -> Self {
        let features = ServerFeatures(client: client)
        return Self(
            server: { song in
                let duration = song.duration.map(Double.init)
                if await features.supportsSongLyrics() {
                    let sets = try await client.structuredLyrics(songID: song.id)
                    // Prefer a synced set; otherwise any with words.
                    if let synced = sets.first(where: { $0.synced }) {
                        return synced.lyrics(songDuration: duration, source: .server)
                    }
                    if let plain = sets.first(where: { set in set.lines.contains { !$0.value.isEmpty } }) {
                        return plain.lyrics(songDuration: duration, source: .server)
                    }
                }
                guard let text = try await client.plainLyrics(artist: song.artist, title: song.title) else { return nil }
                return Lyrics(plain: text, source: .server)
            },
            online: { song in
                let lookup = try await lrclib.lookUp(
                    title: song.title, artist: song.artist, album: song.album, duration: song.duration
                )
                switch lookup {
                case .found(let found):
                    return LyricsModel.onlineLyrics(from: found, songDuration: song.duration.map(Double.init))
                        ?? .notFound(nil)
                case .notFound(let rejection):
                    return .notFound(rejection)
                }
            },
            // Found among the search's matches: LRCLIB's get-by-id endpoint
            // (`api/get/{id}`) failed most of the time when tried (503s).
            onlineEntry: { song, id in
                let matches = try await lrclib.matches(title: song.title, artist: song.artist, album: song.album, duration: song.duration)
                guard let found = matches.first(where: { $0.id == id }),
                      case .lyrics(let lyrics) = LyricsModel.onlineLyrics(from: found, songDuration: song.duration.map(Double.init))
                else { return nil }
                return lyrics
            },
            onlineMatches: { song in
                try await lrclib.matches(title: song.title, artist: song.artist, album: song.album, duration: song.duration)
                    .compactMap { found in
                        guard case .lyrics(let lyrics) = LyricsModel.onlineLyrics(from: found, songDuration: song.duration.map(Double.init)) else { return nil }
                        return lyrics
                    }
            }
        )
    }
}

extension LyricsModel {
    /// LRCLIB's answer as lyrics: synced if its LRC has timed lines, else plain.
    nonisolated static func onlineLyrics(from result: LRCLIBClient.Result, songDuration: TimeInterval?) -> OnlineLyrics? {
        if let synced = result.synced {
            let timed = LRC.parse(synced)
            if !timed.isEmpty {
                var lyrics = Lyrics(timed: timed, songDuration: songDuration, source: .lrclib)
                lyrics.lrclibID = result.id
                return .lyrics(lyrics)
            }
        }
        if let plain = result.plain {
            var lyrics = Lyrics(plain: plain, source: .lrclib)
            lyrics.lrclibID = result.id
            return .lyrics(lyrics)
        }
        return result.isInstrumental ? .instrumental : nil
    }
}


