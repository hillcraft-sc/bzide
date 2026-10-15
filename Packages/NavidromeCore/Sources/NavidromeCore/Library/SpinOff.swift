import Foundation
import Observation

/// What a spin-off grows from: a song, or an artist. Saved with the queue so
/// a spin-off keeps going after the app restarts.
public enum SpinOffSeed: Codable, Equatable, Sendable {
    case song(id: String, title: String, genre: String?)
    case artist(id: String, name: String)

    public init(song: Song) {
        self = .song(id: song.id, title: song.title, genre: song.genre)
    }

    /// What it's named after, for showing: the song title or artist name.
    public var title: String {
        switch self {
        case .song(_, let title, _): title
        case .artist(_, let name): name
        }
    }

    var genre: String? {
        if case .song(_, _, let genre) = self { return genre }
        return nil
    }
}

/// Spin Off: an endless run of music grown from a song or an artist.
///
/// The server's similar songs come first (Navidrome with an agent such as
/// Last.fm). A server without them (no agent, or plain Subsonic) gets a mix
/// instead: random songs from the seed's genre, or from the whole library,
/// and a notice says so. Either way the music plays, on any server.
///
/// When only a couple of songs are left, more are added without a gap,
/// leaving out anything already in the queue, even while the user skips
/// through. Starting a spin-off turns repeat off; turned back on, repeat loops
/// the queue instead of growing it. With Keep Spinning on, a queue that
/// reaches its last song spins off from it in the same way (not with repeat on).
@MainActor
@Observable
public final class SpinOffModel {
    /// Where the songs come from.
    public struct Sources: Sendable {
        public var similarToSong: @Sendable (_ songID: String) async throws -> [Song]
        public var similarToArtist: @Sendable (_ artistID: String) async throws -> [Song]
        public var random: @Sendable (_ genre: String?) async throws -> [Song]

        public init(
            similarToSong: @escaping @Sendable (String) async throws -> [Song],
            similarToArtist: @escaping @Sendable (String) async throws -> [Song],
            random: @escaping @Sendable (String?) async throws -> [Song]
        ) {
            self.similarToSong = similarToSong
            self.similarToArtist = similarToArtist
            self.random = random
        }
    }

    /// Songs to add, and whether they're a mix standing in for similar songs.
    public struct Batch: Equatable, Sendable {
        public var songs: [Song]
        /// `nil` when they're similar songs; otherwise the genre mixed from, or "" for the whole library.
        public var mixedFrom: String?
    }

    /// Songs per batch, and how few left in the queue fetches the next.
    public static let batchSize = 25
    public static let refillWhenLeft = 2

    /// A message for the user, shown briefly (why a mix, or what went wrong).
    public private(set) var notice: String?
    public private(set) var isStarting = false

    @ObservationIgnored private let engine: PlaybackEngine
    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private let keepSpinning: @MainActor () -> Bool
    @ObservationIgnored private var isRefilling = false

    public init(engine: PlaybackEngine, sources: Sources, keepSpinning: @escaping @MainActor () -> Bool) {
        self.engine = engine
        self.sources = sources
        self.keepSpinning = keepSpinning
        engine.onQueueRunningLow = { [weak self] in
            guard let self else { return }
            Task { await self.queueRunningLow() }
        }
    }

    /// Plays the song, then music grown from it.
    public func start(from song: Song) async {
        let seed = SpinOffSeed(song: song)
        await start(seed, first: [song])
    }

    /// Plays music grown from the artist.
    public func start(fromArtist artist: Artist) async {
        await start(.artist(id: artist.id, name: artist.name), first: [])
    }

    public func dismissNotice() {
        notice = nil
    }

    private func start(_ seed: SpinOffSeed, first: [Song]) async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        notice = nil
        guard let batch = await Self.batch(for: seed, excluding: Set(first.map(\.id)), sources: sources) else {
            notice = "Couldn't spin off \u{201C}\(seed.title)\u{201D}. Check your connection and try again."
            return
        }
        engine.startSpinOff(seed, songs: first + batch.songs)
        notice = Self.mixNotice(batch)
    }

    /// Adds the next batch when the queue is nearly done, for a spin-off, or
    /// with Keep Spinning on for any queue on its last song.
    func queueRunningLow() async {
        guard !isRefilling, engine.repeatMode == .off, let current = engine.queue.current?.song, !current.isLive else { return }
        let seed: SpinOffSeed
        if let spinOff = engine.spinOff {
            seed = spinOff
        } else if keepSpinning(), !engine.queue.hasNext {
            seed = SpinOffSeed(song: current)
        } else {
            return
        }
        isRefilling = true
        defer { isRefilling = false }
        let inQueue = Set(engine.queue.entries.map(\.song.id))
        let queueStart = engine.queue.entries.first?.id
        guard let batch = await Self.batch(for: seed, excluding: inQueue, sources: sources) else { return }
        // Still the same queue: skipping songs meanwhile is fine, but playing
        // something else (a new queue) isn't.
        guard engine.queue.entries.first?.id == queueStart else { return }
        engine.continueSpinOff(seed, with: batch.songs)
        // Skipped on while fetching: if it's low again already, top up again.
        if engine.queue.upNext.count <= PlaybackEngine.runningLowCount {
            await queueRunningLow()
        }
    }

    /// Similar songs if the server has any, otherwise a mix from the seed's
    /// genre, otherwise from the whole library. Songs in `excluding` and
    /// repeats are left out. `nil` if nothing could be found.
    static func batch(for seed: SpinOffSeed, excluding: Set<String>, sources: Sources) async -> Batch? {
        let similar: [Song]
        switch seed {
        case .song(let id, _, _): similar = (try? await sources.similarToSong(id)) ?? []
        case .artist(let id, _): similar = (try? await sources.similarToArtist(id)) ?? []
        }
        let unheard = fresh(similar, excluding: excluding)
        if !unheard.isEmpty {
            return Batch(songs: Array(unheard.shuffled().prefix(batchSize)), mixedFrom: nil)
        }
        if let genre = seed.genre {
            let mix = fresh((try? await sources.random(genre)) ?? [], excluding: excluding)
            if !mix.isEmpty { return Batch(songs: Array(mix.prefix(batchSize)), mixedFrom: genre) }
        }
        let mix = fresh((try? await sources.random(nil)) ?? [], excluding: excluding)
        return mix.isEmpty ? nil : Batch(songs: Array(mix.prefix(batchSize)), mixedFrom: "")
    }

    /// Without songs already queued, radio, or repeats.
    private static func fresh(_ songs: [Song], excluding: Set<String>) -> [Song] {
        var seen = excluding
        return songs.filter { !$0.isLive && seen.insert($0.id).inserted }
    }

    /// Explains a mix, so someone whose server has no similar songs knows why.
    static func mixNotice(_ batch: Batch) -> String? {
        guard let source = batch.mixedFrom else { return nil }
        let mix = source.isEmpty ? "a random mix from your library" : "a mix of \(source)"
        return "Similar songs aren't available from this server, so this is \(mix)."
    }
}
