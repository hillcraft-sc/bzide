import Foundation
import Observation
import os

/// Keeps the queue on the server too, so it can be continued on another
/// device, or picked up from another app (Gitea #37). Settings > Playback >
/// Sync Queue with Server, on by default; only the user's own server is told.
///
/// Saving: a few seconds after the song, the queue, or playing and paused
/// change (so a run of skips saves once), and right away when the app goes to
/// the background. Songs only: a radio station can't be in a Subsonic play
/// queue, so while one plays the server keeps the last songs. A long queue is
/// saved as a window around the current song.
///
/// Picking up: on launch and on coming back to the app, the server's queue is
/// read. If it isn't the one this device saved last (another device or app
/// saved since), isn't what's here already, and wasn't turned down, it's
/// offered (`offer`); nothing changes unless the user continues it.
@MainActor
@Observable
public final class QueueSync {
    public struct Sources: Sendable {
        public var save: @Sendable (ServerPlayQueue) async throws -> Void
        public var load: @Sendable () async throws -> ServerPlayQueue?
        /// The most songs to save: fewer when the server can't take a form POST.
        public var songLimit: @Sendable () async -> Int

        public init(
            save: @escaping @Sendable (ServerPlayQueue) async throws -> Void,
            load: @escaping @Sendable () async throws -> ServerPlayQueue?,
            songLimit: @escaping @Sendable () async -> Int = { QueueSync.postSongLimit }
        ) {
            self.save = save
            self.load = load
            self.songLimit = songLimit
        }
    }

    /// A queue saved somewhere else, to offer; `nil` when there's none.
    public private(set) var offer: ServerPlayQueue?

    /// Songs saved at most, as a form POST, and in a URL (which servers and
    /// proxies cap at a few kilobytes).
    public nonisolated static let postSongLimit = 500
    public nonisolated static let urlSongLimit = 150
    /// Songs kept before the current one when a long queue is cut to a window.
    static let songsBefore = 10
    static let saveDelay: TimeInterval = 3

    @ObservationIgnored private let engine: PlaybackEngine
    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private let isOn: @MainActor () -> Bool
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private var marks: Marks
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var isChecking = false
    /// One save at a time; a change during one saves again after it.
    @ObservationIgnored private var isSaving = false
    @ObservationIgnored private var savesAgain = false

    public nonisolated static let fileName = "QueueSync.json"
    private static let logger = Logger(subsystem: "MusicApp", category: "QueueSync")

    /// What was saved last from here, and the last offer turned down.
    struct Marks: Codable, Equatable {
        var saved: Mark?
        var declined: Mark?
    }

    /// A queue, by its songs, current song and position (to the second).
    struct Mark: Codable, Equatable {
        var songIDs: [String]
        var currentIndex: Int
        var position: Int

        init(_ queue: ServerPlayQueue) {
            songIDs = queue.songs.map(\.id)
            currentIndex = queue.currentIndex
            position = Int(queue.position.rounded())
        }

        /// The same songs and song, within a couple of seconds.
        func matches(_ other: Mark) -> Bool {
            songIDs == other.songIDs && currentIndex == other.currentIndex && abs(position - other.position) <= 2
        }
    }

    public init(
        engine: PlaybackEngine, sources: Sources, isOn: @escaping @MainActor () -> Bool, fileURL: URL?,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.engine = engine
        self.sources = sources
        self.isOn = isOn
        self.fileURL = fileURL
        self.sleep = sleep
        marks = fileURL.flatMap { try? JSONDecoder().decode(Marks.self, from: Data(contentsOf: $0)) } ?? Marks()
    }

    /// Starts following the engine.
    public func start() {
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = engine.queue.current?.id
            _ = engine.queue.entries.map(\.id)
            _ = engine.status == .playing
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
                self?.scheduleSave()
            }
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self, sleep] in
            await sleep(Self.saveDelay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// The app is going to the background: save now, with the position.
    public func saveNow() async {
        pendingSave?.cancel()
        pendingSave = nil
        await save()
    }

    func save() async {
        guard !isSaving else {
            savesAgain = true
            return
        }
        isSaving = true
        defer { isSaving = false }
        repeat {
            savesAgain = false
            await saveOnce()
        } while savesAgain
    }

    private func saveOnce() async {
        guard isOn(), let queue = await songsToSave() else { return }
        let mark = Mark(queue)
        if let saved = marks.saved, saved.matches(mark) { return }
        do {
            try await sources.save(queue)
            marks.saved = mark
            // This queue is now the server's; an older offer is moot.
            offer = nil
            store()
        } catch {
            // Tried again at the next change, or the next time the app leaves.
            Self.logger.error("Couldn't save the queue to the server: \(String(describing: error), privacy: .public)")
        }
    }

    /// The queue's songs, cut to a window around the current one; `nil` when
    /// there are none, or a station is playing.
    func songsToSave() async -> ServerPlayQueue? {
        let entries = engine.queue.entries
        guard let current = engine.queue.current, !current.song.isLive else { return nil }
        let songs = entries.filter { !$0.song.isLive }
        guard let index = songs.firstIndex(where: { $0.id == current.id }) else { return nil }
        let limit = max(await sources.songLimit(), 1)
        let start = max(0, min(index - Self.songsBefore, songs.count - limit))
        let window = Array(songs[start..<min(start + limit, songs.count)])
        return ServerPlayQueue(songs: window.map(\.song), currentIndex: index - start, position: engine.position)
    }

    /// On launch and on coming back: offers the server's queue if it was
    /// saved somewhere else since.
    public func checkServer() async {
        guard isOn(), !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let found: ServerPlayQueue?
        do {
            found = try await sources.load()
        } catch {
            Self.logger.error("Couldn't read the server's queue: \(String(describing: error), privacy: .public)")
            return
        }
        guard let found, found.current != nil else { return }
        let mark = Mark(found)
        if let saved = marks.saved, saved.matches(mark) { return }
        if let declined = marks.declined, declined.matches(mark) { return }
        if let here = await songsToSave(), Mark(here).songIDs == mark.songIDs, Mark(here).currentIndex == mark.currentIndex {
            // Already here (say, saved by this device before the marks were kept).
            return
        }
        offer = found
    }

    /// Plays the offered queue, from its song and position.
    public func continueOffer() {
        guard let queue = offer else { return }
        offer = nil
        engine.play(songs: queue.songs, startIndex: queue.currentIndex, from: queue.position)
    }

    /// Not now: this queue isn't offered again (a newer one will be).
    public func declineOffer() {
        guard let queue = offer else { return }
        offer = nil
        marks.declined = Mark(queue)
        store()
    }

    /// Settings turned it off: nothing is offered.
    public func turnedOff() {
        pendingSave?.cancel()
        offer = nil
    }

    private func store() {
        guard let fileURL, let data = try? JSONEncoder().encode(marks) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

extension ServerPlayQueue {
    /// The banner's question: "Continue “Karma Police”?"
    public var offerTitle: String {
        "Continue “\(current?.title ?? "your queue")”?"
    }

    /// Where it's from: "From Bzide on another device, 5 minutes ago",
    /// "From Feishin, yesterday".
    public func offerDetail(now: Date = .now, ownName: String = ClientIdentity().name) -> String {
        let app = changedBy.map { $0 == ownName ? "From \($0) on another device" : "From \($0)" } ?? "From another device"
        guard let changed else { return app }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        // The server's clock may run a little ahead of this one's.
        return app + ", " + formatter.localizedString(for: min(changed, now), relativeTo: now)
    }
}
