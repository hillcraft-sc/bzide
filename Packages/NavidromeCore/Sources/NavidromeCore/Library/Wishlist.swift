import Foundation
import Observation

/// A song heard on the radio that the user wants to remember (and maybe get).
public struct WishlistEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var artist: String
    public var title: String
    /// The station it was heard on.
    public var station: String?
    public var heardAt: Date
    /// From MusicBrainz, if it was looked up.
    public var album: String?
    public var year: Int?
    public var coverURL: URL?
    public var musicBrainzURL: URL?

    public init(
        id: UUID = UUID(), artist: String, title: String, station: String? = nil, heardAt: Date,
        album: String? = nil, year: Int? = nil, coverURL: URL? = nil, musicBrainzURL: URL? = nil
    ) {
        self.id = id
        self.artist = artist
        self.title = title
        self.station = station
        self.heardAt = heardAt
        self.album = album
        self.year = year
        self.coverURL = coverURL
        self.musicBrainzURL = musicBrainzURL
    }

    var song: OnAirSong { OnAirSong(artist: artist, title: title) }

    /// "Paul McCartney - Band on the Run", for copying.
    public var text: String { "\(artist) - \(title)" }
}

/// Songs heard on the radio to remember, shown to users as "Tagged Radio
/// Songs" (Wishlist is its name in code and in the saved file): added from Now Playing while a
/// station plays a song that isn't in the library. Kept on this iPhone only,
/// in a file, whichever account is signed in (it's about music heard, not a
/// server's library), and never sent anywhere. Newest first.
///
/// Opening the list checks the user's server for each song (as Now Playing's
/// "In Your Library" does); one found there is marked, with the library's
/// copy to play, and stays until the user removes it.
@MainActor
@Observable
public final class Wishlist {
    nonisolated public static let fileName = "Wishlist.json"

    public private(set) var entries: [WishlistEntry]
    /// Entries found in the library since, with the library's song.
    public private(set) var owned: [UUID: Song] = [:]

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let search: OnAirMatchModel.Search
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(fileURL: URL?, search: @escaping OnAirMatchModel.Search, now: @escaping @Sendable () -> Date = { .now }) {
        self.fileURL = fileURL
        self.search = search
        self.now = now
        entries = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(LossyList<WishlistEntry>.self, from: $0).items }
            ?? []
    }

    /// Whether the song is on the list already (the same title and artist,
    /// as Now Playing's matching goes).
    public func contains(_ song: OnAirSong) -> Bool {
        entries.contains { song.matches(Song(id: $0.id.uuidString, title: $0.title, artist: $0.artist)) }
    }

    /// Adds the song (once), with what MusicBrainz found, if anything.
    public func add(_ song: OnAirSong, station: String?, details: OnAirDetails?) {
        guard !contains(song) else { return }
        let entry = WishlistEntry(
            artist: details?.artist ?? song.artist, title: details?.title ?? song.title, station: station, heardAt: now(),
            album: details?.album, year: details?.year, coverURL: details?.coverURL, musicBrainzURL: details?.musicBrainzURL
        )
        entries.insert(entry, at: 0)
        save()
    }

    public func remove(_ id: WishlistEntry.ID) {
        entries.removeAll { $0.id == id }
        owned[id] = nil
        save()
    }

    /// Looks each song up on the user's server and marks those found. A
    /// search that fails leaves that song as it was.
    public func checkLibrary() async {
        for entry in entries {
            guard owned[entry.id] == nil else { continue }
            let song = entry.song
            for query in ["\(song.artist) \(song.title)", song.title, song.artist] {
                guard let results = try? await search(query) else { break }
                if let found = results.first(where: song.matches) {
                    owned[entry.id] = found
                    break
                }
            }
        }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
