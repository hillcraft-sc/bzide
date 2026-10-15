import Foundation
import Observation

/// Something the Library screen can show.
public enum LibraryFeature: String, CaseIterable, Codable, Sendable {
    case recentlyAdded, randomMix, ratedShuffle, artists, albums, playlists, favorites, genres, radio, downloads, history

    public var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .randomMix: "Random Mix"
        case .ratedShuffle: "Shuffle Rated"
        case .artists: "Artists"
        case .albums: "Albums"
        case .playlists: "Playlists"
        case .favorites: "Favorites"
        case .genres: "Genres"
        case .radio: "Radio"
        case .downloads: "Downloaded"
        case .history: "History"
        }
    }

    /// Plays something at once (Random Mix, Shuffle Rated) rather than opening a list.
    public var isMix: Bool {
        self == .randomMix || self == .ratedShuffle
    }

    /// Opens a list, rather than being a section of its own.
    public var isLink: Bool {
        self != .recentlyAdded && !isMix
    }
}

/// What the Library screen shows, and in what order. Everything is shown by
/// default; the user can hide items and reorder them.
public struct LibraryLayout: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var item: LibraryFeature
        public var isShown: Bool
    }

    public private(set) var entries: [Entry]

    public init() {
        entries = LibraryFeature.allCases.map { Entry(item: $0, isShown: true) }
    }

    /// The shown items, in order.
    public var shown: [LibraryFeature] {
        entries.filter(\.isShown).map(\.item)
    }

    /// Moves the entries at `source` to before the entry that was at
    /// `destination`, as a list's drag to reorder reports it.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { entries.indices.contains($0) }
        let moving = valid.map { entries[$0] }
        var remaining = entries.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let insertAt = min(max(destination - valid.filter { $0 < destination }.count, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: insertAt)
        entries = remaining
    }

    public mutating func setShown(_ item: LibraryFeature, _ isShown: Bool) {
        guard let index = entries.firstIndex(where: { $0.item == item }) else { return }
        entries[index].isShown = isShown
    }

    /// How the Library screen draws the shown items: Recently Added on its
    /// own; mixes (Random Mix, Shuffle Rated) next to each other in one block;
    /// links next to each other in another.
    public enum Group: Equatable, Sendable {
        case recentlyAdded
        case mixes([LibraryFeature])
        case links([LibraryFeature])
    }

    public var groups: [Group] {
        var groups: [Group] = []
        for item in shown {
            if item == .recentlyAdded {
                groups.append(.recentlyAdded)
            } else if item.isMix {
                if case .mixes(let mixes) = groups.last {
                    groups[groups.count - 1] = .mixes(mixes + [item])
                } else {
                    groups.append(.mixes([item]))
                }
            } else if case .links(let links) = groups.last {
                groups[groups.count - 1] = .links(links + [item])
            } else {
                groups.append(.links([item]))
            }
        }
        return groups
    }

    // MARK: - Saving

    private enum CodingKeys: String, CodingKey { case entries }

    /// Lenient, so a layout saved by another version still works: unknown
    /// items and repeats are dropped, and items added since (like a new kind
    /// of list) appear, shown, in their usual place: after the item that
    /// comes before them by default (or first, if that's missing too).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let saved = (try? c.decode([LossyEntry].self, forKey: .entries)) ?? []
        var seen = Set<LibraryFeature>()
        var entries: [Entry] = []
        for case let entry? in saved.map(\.entry) where seen.insert(entry.item).inserted {
            entries.append(entry)
        }
        let all = LibraryFeature.allCases
        for (position, item) in all.enumerated() where !seen.contains(item) {
            // After the nearest item before it in the default order that's there.
            let before = all[..<position].reversed().first { previous in entries.contains { $0.item == previous } }
            let index = before.flatMap { previous in entries.firstIndex { $0.item == previous } }.map { $0 + 1 } ?? 0
            entries.insert(Entry(item: item, isShown: true), at: index)
            seen.insert(item)
        }
        self.entries = entries
    }

    /// An entry whose item this version doesn't know decodes as `nil`.
    private struct LossyEntry: Decodable {
        let entry: Entry?

        init(from decoder: any Decoder) throws {
            entry = try? Entry(from: decoder)
        }
    }
}

/// The Library screen's layout, saved to `UserDefaults` on every change.
/// Device-wide, like appearance: it stays across sign-outs.
@MainActor
@Observable
public final class LibraryLayoutModel {
    public var layout: LibraryLayout {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    static let key = "libraryLayout"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layout = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(LibraryLayout.self, from: $0) }
            ?? LibraryLayout()
    }

    public func reset() {
        layout = LibraryLayout()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
