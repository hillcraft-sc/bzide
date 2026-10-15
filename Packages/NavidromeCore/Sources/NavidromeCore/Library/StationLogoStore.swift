import Foundation

/// Remembers which logo goes with which station, by stream address: logos
/// found when a station is added from Find Stations, and ones looked up on
/// Radio Browser for stations added elsewhere. "No logo" is remembered too,
/// so a station is looked up only once. Kept in a file, as part of the
/// account's data (see `AccountScope`); without a file (in tests) it lasts as
/// long as the store.
public final class StationLogoStore: @unchecked Sendable {
    nonisolated public static let fileName = "StationLogos.json"

    /// What's known about a stream's logo.
    public enum Entry: Equatable, Sendable {
        case logo(URL)
        /// Looked up: there's none. (Not `none`, which an optional would
        /// read as "nothing known".)
        case noLogo
    }

    private let fileURL: URL?
    private let lock = NSLock()
    /// Stream address → logo address, or "" for none.
    private var entries: [String: String]

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        entries = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
            ?? [:]
    }

    /// `nil` if nothing is known about this stream yet.
    public func entry(for stream: URL) -> Entry? {
        lock.withLock {
            guard let value = entries[stream.absoluteString] else { return nil }
            return StationLogo.usableURL(value).map(Entry.logo) ?? .noLogo
        }
    }

    public func set(_ entry: Entry, for stream: URL) {
        let data: Data? = lock.withLock {
            switch entry {
            case .logo(let url): entries[stream.absoluteString] = url.absoluteString
            case .noLogo: entries[stream.absoluteString] = ""
            }
            return try? JSONEncoder().encode(entries)
        }
        guard let fileURL, let data else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
