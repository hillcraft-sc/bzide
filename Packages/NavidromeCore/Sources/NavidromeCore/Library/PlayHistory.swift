import Foundation
import Observation
import os

/// One counted play: the song as it was when played, and when it started.
public struct PlayHistoryEntry: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let song: Song
    public let playedAt: Date

    public init(song: Song, playedAt: Date, id: UUID = UUID()) {
        self.id = id
        self.song = song
        self.playedAt = playedAt
    }

    /// Whether the title, artist or album contains `query`, ignoring case and
    /// accents. An empty query matches everything.
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let fields: [String?] = [song.title, song.artist, song.album]
        return fields.contains { $0?.localizedStandardContains(query) == true }
    }
}

/// How long plays are kept.
public enum HistoryRetention: Int, CaseIterable, Sendable, Codable {
    case week = 7
    case month = 30
    case quarter = 90
    case year = 365
    case forever = 0

    public var title: String {
        switch self {
        case .week: "7 Days"
        case .month: "30 Days"
        case .quarter: "90 Days"
        case .year: "1 Year"
        case .forever: "Forever"
        }
    }

    /// Plays before this are dropped; `nil` keeps everything.
    func cutoff(now: Date, calendar: Calendar) -> Date? {
        self == .forever ? nil : calendar.date(byAdding: .day, value: -rawValue, to: now)
    }
}

/// Which plays the history screen shows.
public enum HistoryPeriod: Sendable, Equatable, Hashable {
    case today
    case lastWeek
    case lastMonth
    case all
    /// Whole days, from the start of the first to the end of the last.
    case custom(from: Date, to: Date)

    public static let presets: [HistoryPeriod] = [.today, .lastWeek, .lastMonth, .all]

    public var title: String {
        switch self {
        case .today: "Today"
        case .lastWeek: "Last 7 Days"
        case .lastMonth: "Last 30 Days"
        case .all: "All"
        case .custom: "Custom"
        }
    }

    /// `nil` means no limit.
    func interval(now: Date, calendar: Calendar) -> DateInterval? {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return DateInterval(start: startOfToday, end: now)
        case .lastWeek:
            return calendar.date(byAdding: .day, value: -6, to: startOfToday).map { DateInterval(start: $0, end: now) }
        case .lastMonth:
            return calendar.date(byAdding: .day, value: -29, to: startOfToday).map { DateInterval(start: $0, end: now) }
        case .all:
            return nil
        case .custom(let from, let to):
            let start = calendar.startOfDay(for: min(from, to))
            let lastDay = calendar.startOfDay(for: max(from, to))
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            return DateInterval(start: start, end: end)
        }
    }
}

/// The plays of one calendar day, newest first.
public struct HistoryDay: Sendable, Equatable, Identifiable {
    public let day: Date
    public let entries: [PlayHistoryEntry]
    public var id: Date { day }
}

/// Receives each counted play from the engine.
@MainActor
public protocol PlayRecording: AnyObject {
    func record(_ song: Song, playedAt: Date)
}

/// What the user has played, kept on this device only (the Subsonic API has no
/// list of plays to sync with). A play is recorded when it counts for
/// scrobbling. Plays older than the retention setting are dropped on launch,
/// on every new play, and when the setting changes.
@MainActor
@Observable
public final class PlayHistory: PlayRecording {
    /// Newest first.
    public private(set) var entries: [PlayHistoryEntry] = []
    public var retention: HistoryRetention {
        didSet {
            defaults.set(retention.rawValue, forKey: Self.retentionKey)
            prune()
        }
    }

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    static let retentionKey = "historyRetention"
    private static let logger = Logger(subsystem: "MusicApp", category: "PlayHistory")

    public init(
        fileURL: URL,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        retention = defaults.object(forKey: Self.retentionKey).flatMap { $0 as? Int }.flatMap(HistoryRetention.init) ?? .month
        entries = Self.load(from: fileURL)
        prune()
    }

    /// `Application Support/PlayHistory.json`.
    public static func applicationSupportFile() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "PlayHistory.json")
    }

    public func record(_ song: Song, playedAt: Date) {
        let entry = PlayHistoryEntry(song: song, playedAt: playedAt)
        let index = entries.firstIndex { $0.playedAt <= playedAt } ?? entries.endIndex
        entries.insert(entry, at: index)
        prune()
        save()
    }

    public func clear() {
        entries = []
        save()
    }

    /// The plays in `period` that match `query`, grouped by day, newest first.
    public func days(matching query: String, in period: HistoryPeriod) -> [HistoryDay] {
        let interval = period.interval(now: now(), calendar: calendar)
        var days: [HistoryDay] = []
        var currentDay: Date?
        var currentEntries: [PlayHistoryEntry] = []
        for entry in entries {
            if let interval, !interval.contains(entry.playedAt) { continue }
            guard entry.matches(query) else { continue }
            let day = calendar.startOfDay(for: entry.playedAt)
            if day != currentDay, let finished = currentDay {
                days.append(HistoryDay(day: finished, entries: currentEntries))
                currentEntries = []
            }
            currentDay = day
            currentEntries.append(entry)
        }
        if let currentDay {
            days.append(HistoryDay(day: currentDay, entries: currentEntries))
        }
        return days
    }

    // MARK: - Storage

    private func prune() {
        guard let cutoff = retention.cutoff(now: now(), calendar: calendar) else { return }
        let kept = entries.filter { $0.playedAt >= cutoff }
        guard kept.count != entries.count else { return }
        entries = kept
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            // Plays are recorded during locked-screen playback.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.logger.error("Couldn't save play history: \(String(describing: error), privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [PlayHistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([PlayHistoryEntry].self, from: data).sorted { $0.playedAt > $1.playedAt }
        } catch {
            logger.error("Play history unreadable, starting empty: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}
