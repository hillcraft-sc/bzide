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
/// equals. Results are kept for the session, so reopening is instant.
@MainActor
@Observable
public final class LyricsModel {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded(Lyrics)
        /// LRCLIB knows the song has no words.
        case instrumental
        case none
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
    }

    public private(set) var state: State = .idle
    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private var cache: [String: State] = [:]
    @ObservationIgnored private var loadingKey: String?

    public init(sources: Sources) {
        self.sources = sources
    }

    /// Loads lyrics for `song` unless they're already showing. A newer
    /// request always wins: a slow answer for an earlier song is dropped.
    public func load(_ song: Song?, onlineAllowed: Bool) async {
        guard let song else {
            loadingKey = nil
            state = .none
            return
        }
        guard !song.isLive else {
            loadingKey = nil
            state = .radio
            return
        }
        let key = "\(song.id)|\(onlineAllowed)"
        if let cached = cache[key] {
            loadingKey = nil
            state = cached
            return
        }
        guard loadingKey != key else { return }
        loadingKey = key
        state = .loading
        let result = await find(song, onlineAllowed: onlineAllowed)
        // Another song may have been asked for meanwhile.
        guard loadingKey == key else { return }
        loadingKey = nil
        if case .failed = result {} else {
            cache[key] = result
        }
        state = result
    }

    private func find(_ song: Song, onlineAllowed: Bool) async -> State {
        var serverFailed = false
        var server: Lyrics?
        do {
            server = try await sources.server(song)
        } catch {
            serverFailed = true
        }
        if let server, server.isSynced { return .loaded(server) }

        var onlineFailed = false
        var online: OnlineLyrics?
        if onlineAllowed {
            do {
                online = try await sources.online(song)
            } catch {
                onlineFailed = true
            }
        }
        if case .lyrics(let lyrics) = online, lyrics.isSynced { return .loaded(lyrics) }
        if let server { return .loaded(server) }
        if case .lyrics(let lyrics) = online { return .loaded(lyrics) }
        if case .instrumental = online { return .instrumental }
        // Nothing found: say so, unless nothing could be asked.
        let couldAsk = !serverFailed || (onlineAllowed && !onlineFailed)
        return couldAsk ? .none : .failed("Couldn't load lyrics. Check your connection and try again.")
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
                guard let found = try await lrclib.lyrics(
                    title: song.title, artist: song.artist, album: song.album, duration: song.duration
                ) else { return nil }
                return LyricsModel.onlineLyrics(from: found, songDuration: song.duration.map(Double.init))
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
