import Foundation

/// One slot in the queue. The same song can be queued more than once, so each
/// entry has its own identity separate from the song's id.
public struct QueueEntry: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    public let song: Song

    public init(song: Song, id: UUID = UUID()) {
        self.id = id
        self.song = song
    }
}

/// The ordered list of songs to play and which one is current.
///
/// Pure value type: no audio, no I/O. The playback engine owns one and is the only
/// thing that mutates it. Rules are in docs/BEHAVIOR.md under "Queue".
public struct PlaybackQueue: Sendable, Equatable, Codable {
    public private(set) var entries: [QueueEntry]
    /// `nil` only when the queue is empty.
    public private(set) var currentIndex: Int?

    public init() {
        entries = []
        currentIndex = nil
    }

    /// A new queue starting at `startIndex`, clamped into range.
    public init(songs: [Song], startIndex: Int = 0) {
        entries = songs.map { QueueEntry(song: $0) }
        currentIndex = songs.isEmpty ? nil : min(max(startIndex, 0), songs.count - 1)
    }

    public var isEmpty: Bool { entries.isEmpty }

    public var current: QueueEntry? {
        currentIndex.map { entries[$0] }
    }

    /// Everything after the current entry.
    public var upNext: ArraySlice<QueueEntry> {
        guard let currentIndex else { return [] }
        return entries[(currentIndex + 1)...]
    }

    public var hasNext: Bool { !upNext.isEmpty }

    /// The current entry and everything after it: what the queue shows. Earlier
    /// entries are kept, out of sight, so previous can go back to them.
    public var fromCurrent: ArraySlice<QueueEntry> {
        guard let currentIndex else { return [] }
        return entries[currentIndex...]
    }

    public var hasPrevious: Bool { (currentIndex ?? 0) > 0 }

    /// Moves to the next entry. Returns `false` (and stays put) at the end.
    @discardableResult
    public mutating func advance() -> Bool {
        guard let currentIndex, hasNext else { return false }
        self.currentIndex = currentIndex + 1
        return true
    }

    /// Moves to the previous entry. Returns `false` (and stays put) at the start.
    @discardableResult
    public mutating func goBack() -> Bool {
        guard let currentIndex, hasPrevious else { return false }
        self.currentIndex = currentIndex - 1
        return true
    }

    /// Makes the entry with this id current. Returns `false` if it isn't in the queue.
    @discardableResult
    public mutating func jump(to entryID: QueueEntry.ID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return false }
        currentIndex = index
        return true
    }

    /// Inserts songs right after the current entry, ahead of everything else
    /// upcoming. An empty queue behaves like `append`.
    public mutating func insertNext(_ songs: [Song]) {
        guard let currentIndex else {
            append(songs)
            return
        }
        entries.insert(contentsOf: songs.map { QueueEntry(song: $0) }, at: currentIndex + 1)
    }

    /// Removes everything after the current entry.
    public mutating func removeUpcoming() {
        guard let currentIndex else { return }
        entries.removeSubrange((currentIndex + 1)...)
    }

    /// Removes one upcoming entry. The current entry and the ones already
    /// played can't be removed this way. Returns `false` if nothing was removed.
    @discardableResult
    public mutating func removeUpcoming(_ entryID: QueueEntry.ID) -> Bool {
        guard let currentIndex,
              let index = entries.firstIndex(where: { $0.id == entryID }),
              index > currentIndex else { return false }
        entries.remove(at: index)
        return true
    }

    /// Reorders the upcoming entries. Offsets count within `upNext` (0 is the
    /// next entry), as a list's move gives them: the moved entries land before
    /// whatever was at `destination`, keeping their order.
    public mutating func moveUpcoming(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard let currentIndex else { return }
        var upcoming = Array(entries[(currentIndex + 1)...])
        let valid = offsets.filter { upcoming.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { upcoming[$0] }
        let clamped = min(max(destination, 0), upcoming.count)
        let target = clamped - valid.filter { $0 < clamped }.count
        for offset in valid.reversed() {
            upcoming.remove(at: offset)
        }
        upcoming.insert(contentsOf: moving, at: target)
        entries.replaceSubrange((currentIndex + 1)..., with: upcoming)
    }

    /// Adds songs to the end. If the queue was empty, the first added song becomes current.
    public mutating func append(_ songs: [Song]) {
        entries.append(contentsOf: songs.map { QueueEntry(song: $0) })
        if currentIndex == nil, !entries.isEmpty {
            currentIndex = 0
        }
    }
}

extension PlaybackQueue {
    private enum CodingKeys: String, CodingKey { case entries, currentIndex }

    /// A saved queue is untrusted input: an index outside the entries would crash
    /// `current`, so it is clamped back into range.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decode([QueueEntry].self, forKey: .entries)
        let index = try c.decodeIfPresent(Int.self, forKey: .currentIndex) ?? 0
        currentIndex = entries.isEmpty ? nil : min(max(index, 0), entries.count - 1)
    }
}

/// What happens when a track or the queue ends.
public enum RepeatMode: String, Sendable, Codable, CaseIterable {
    case off
    /// The queue starts again from the first entry.
    case all
    /// The current track plays again.
    case one

    /// The order the repeat button steps through.
    public var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// What the previous button does, given how far into the current track we are.
public enum PreviousAction: Sendable, Equatable {
    case restartCurrent
    case goToPrevious

    /// Past this many seconds, previous restarts the track instead of going back.
    public static let restartThreshold: TimeInterval = 3

    public static func decide(elapsed: TimeInterval, hasPrevious: Bool) -> PreviousAction {
        (elapsed > restartThreshold || !hasPrevious) ? .restartCurrent : .goToPrevious
    }
}
