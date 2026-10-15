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
        public var online: @Sendable (Song) async throws -> OnlineLyrics?

        public init(
            server: @escaping @Sendable (Song) async throws -> Lyrics?,
            online: @escaping @Sendable (Song) async throws -> OnlineLyrics?
        ) {
            self.server = server
            self.online = online
        }
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

    public private(set) var state: State = .idle
    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private var cache: [String: State] = [:]
    /// Bumped by each load; only the latest load's answer is shown.
    @ObservationIgnored private var generation = 0

    public init(sources: Sources) {
        self.sources = sources
    }

    /// Loads lyrics for `song` unless they're already known. A newer request
    /// always wins: a slow answer for an earlier song is dropped. A canceled
    /// load (the screen closed mid-search) shows and keeps nothing, so the
    /// next one starts afresh.
    public func load(_ song: Song?, onlineAllowed: Bool) async {
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
        let key = "\(song.id)|\(onlineAllowed)"
        if let cached = cache[key] {
            state = cached
            return
        }
        state = .loading
        let found = await find(song, onlineAllowed: onlineAllowed)
        // Another load started meanwhile, or this one was canceled.
        guard mine == generation, !Task.isCancelled, let found else { return }
        // A failure is tried again next time, so a brief outage isn't kept.
        if found.isComplete { cache[key] = found.state }
        state = found.state
    }

    /// An answer, and whether every source answered (so it can be kept).
    private struct Found {
        var state: State
        var isComplete: Bool
    }

    /// `nil` if a lookup was canceled.
    private func find(_ song: Song, onlineAllowed: Bool) async -> Found? {
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
        if onlineAllowed {
            do {
                online = try await sources.online(song)
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
        let note = Self.note(onlineAllowed: onlineAllowed, onlineFailed: onlineFailed, online: online)
        return Found(state: .none(note: note), isComplete: isComplete)
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
                return .lyrics(Lyrics(timed: timed, songDuration: songDuration, source: .lrclib))
            }
        }
        if let plain = result.plain {
            return .lyrics(Lyrics(plain: plain, source: .lrclib))
        }
        return result.isInstrumental ? .instrumental : nil
    }
}

/// What the server supports, asked once and remembered. A failed check isn't
/// remembered, so it's tried again next time.
actor ServerFeatures {
    private let client: SubsonicClient
    private var songLyrics: Bool?

    init(client: SubsonicClient) {
        self.client = client
    }

    func supportsSongLyrics() async -> Bool {
        if let songLyrics { return songLyrics }
        guard let extensions = try? await client.openSubsonicExtensions() else { return false }
        let supported = extensions.contains { $0.name == "songLyrics" }
        songLyrics = supported
        return supported
    }
}
