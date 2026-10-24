import Foundation

/// What a spoken "play … in Bzide" can lead to.
public enum AudioMatch: Equatable, Sendable {
    case song(Song)
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)
    /// Carry on with what's queued ("play music in Bzide"); the current song.
    case resume(Song)
    case randomMix

    /// The name Siri compares with what was said.
    public var title: String {
        switch self {
        case .song(let song), .resume(let song): song.title
        case .album(let album): album.name
        case .artist(let artist): artist.name
        case .playlist(let playlist): playlist.name
        case .randomMix: AudioRequestFinder.randomMixTitle
        }
    }
}

/// Answers Siri's audio search (Gitea #34). On iOS 27, Siri sends "play X in
/// Bzide" to the app's audio search and falls back to Apple Music if the
/// answer is empty or slow, so this answers fast and never with nothing when
/// something fits:
/// - A request with nothing named resumes what's queued, or starts a Random
///   Mix when nothing is.
/// - A named one searches the server and matches playlist names at the same
///   time (playlists from a list kept for a while, since the server can't
///   search them), and stops waiting after `deadline` with what it has.
/// - Exact name matches come first, then songs, albums, artists, playlists.
public actor AudioRequestFinder {
    public struct Sources: Sendable {
        public var search: @Sendable (_ query: String) async throws(SubsonicError) -> SearchResult
        public var playlists: @Sendable () async throws(SubsonicError) -> [Playlist]
        /// The queue's current song, if any.
        public var current: @Sendable () async -> Song?

        public init(
            search: @escaping @Sendable (_ query: String) async throws(SubsonicError) -> SearchResult,
            playlists: @escaping @Sendable () async throws(SubsonicError) -> [Playlist],
            current: @escaping @Sendable () async -> Song?
        ) {
            self.search = search
            self.playlists = playlists
            self.current = current
        }
    }

    public static let randomMixTitle = "Random Mix"

    private let sources: Sources
    private let deadline: Duration
    private let playlistsFreshFor: TimeInterval
    private let now: @Sendable () -> Date
    private var playlists: (items: [Playlist], at: Date)?

    public init(
        sources: Sources, deadline: Duration = .seconds(4), playlistsFreshFor: TimeInterval = 10 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sources = sources
        self.deadline = deadline
        self.playlistsFreshFor = playlistsFreshFor
        self.now = now
    }

    /// "Play music in Bzide": what's queued, or a Random Mix.
    public func unspecified() async -> [AudioMatch] {
        if let current = await sources.current() { return [.resume(current)] }
        return [.randomMix]
    }

    /// "Play `query` in Bzide".
    public func find(_ query: String) async -> [AudioMatch] {
        let wanted = Self.whatToPlay(in: query)
        guard !wanted.isEmpty else { return await unspecified() }
        if Self.same(wanted, Self.randomMixTitle) { return [.randomMix] }
        let (found, lists) = await searchAndPlaylists(wanted)
        let candidates: [AudioMatch] =
            (found?.songs.map(AudioMatch.song) ?? [])
            + (found?.albums.map(AudioMatch.album) ?? [])
            + (found?.artists.map(AudioMatch.artist) ?? [])
            + lists.filter { $0.name.localizedStandardContains(wanted) }.map(AudioMatch.playlist)
        let exact = candidates.filter { Self.same($0.title, wanted) }
        return exact + candidates.filter { !Self.same($0.title, wanted) }
    }

    /// Both at once, giving up on whatever isn't back by the deadline.
    private func searchAndPlaylists(_ query: String) async -> (SearchResult?, [Playlist]) {
        enum Part: Sendable {
            case search(SearchResult?)
            case playlists([Playlist])
            case deadline
        }
        let sources = sources
        let deadline = deadline
        let cached = freshPlaylists()
        return await withTaskGroup(of: Part.self) { group in
            group.addTask { .search(try? await sources.search(query)) }
            if cached == nil {
                group.addTask { .playlists((try? await sources.playlists()) ?? []) }
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return .deadline
            }
            var found: SearchResult?
            var searched = false
            var lists = cached
            for await part in group {
                switch part {
                case .search(let result):
                    found = result
                    searched = true
                case .playlists(let fetched):
                    lists = fetched
                    remember(fetched)
                case .deadline:
                    group.cancelAll()
                    return (found, lists ?? [])
                }
                if searched, lists != nil {
                    group.cancelAll()
                    break
                }
            }
            return (found, lists ?? [])
        }
    }

    private func freshPlaylists() -> [Playlist]? {
        guard let playlists, now().timeIntervalSince(playlists.at) < playlistsFreshFor else { return nil }
        return playlists.items
    }

    private func remember(_ fetched: [Playlist]) {
        // An empty list may be a failed fetch; ask again next time.
        guard !fetched.isEmpty else { return }
        playlists = (fetched, now())
    }

    /// How Siri may write the app's name when it hears it as part of the
    /// request rather than as the app ("Bee-zide", or "Bee-side"): Siri wrote
    /// "Bzside" on device, and then searched for music by that name.
    static let appNameSpellings = ["bzide", "bzside", "bzyde", "bee zide", "beezide", "bee-zide", "b-side", "b side", "bside", "bee side", "beeside", "bee-side"]

    /// Asking for nothing in particular: the same as "play music in Bzide".
    static let genericRequests: Set<String> = [
        "", "music", "my music", "some music", "the music", "songs", "my songs", "some songs", "a song", "something",
        "anything", "my library", "tunes", "some tunes", "audio", "play music", "play",
    ]

    /// What Siri's words ask for, without the app's name (a leading or trailing
    /// "in Bzide", "Bzside" or the like) and with generic words ("music", "my
    /// music") reduced to nothing, which means play whatever: resume, or a
    /// Random Mix.
    static func whatToPlay(in query: String) -> String {
        var text = query.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let connectors = ["in", "on", "from", "with", "using", "via"]
        for name in appNameSpellings.sorted(by: { $0.count > $1.count }) {
            if text == name { text = ""; break }
            for connector in connectors where text.hasSuffix(" \(connector) \(name)") {
                text = String(text.dropLast(connector.count + name.count + 2))
            }
            if text.hasSuffix(" \(name)") { text = String(text.dropLast(name.count + 1)) }
            if text.hasPrefix("\(name) ") { text = String(text.dropFirst(name.count + 1)) }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if genericRequests.contains(text) { return "" }
        // The original casing for a real search.
        return text.isEmpty ? "" : Self.restoringCase(text, from: query)
    }

    /// `text` (lowercased) as it appears in `query`, so the server searches
    /// for what was said.
    private static func restoringCase(_ text: String, from query: String) -> String {
        guard let range = query.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) else { return text }
        return String(query[range])
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
