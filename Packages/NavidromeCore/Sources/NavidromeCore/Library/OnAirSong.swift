import Foundation
import Observation

/// The song a radio station says it's playing, read from its announced title
/// (Shoutcast/Icecast `StreamTitle`), which is free text: usually
/// "Artist - Title", sometimes "Title by Artist", and sometimes just the
/// station's name, an ad or a web address, which aren't songs.
public struct OnAirSong: Hashable, Sendable {
    public var artist: String
    public var title: String

    public init(artist: String, title: String) {
        self.artist = artist
        self.title = title
    }

    /// Dashes stations put between artist and title.
    static let separators = [" - ", " – ", " — "]
    /// Words in titles that aren't songs.
    static let notSongs = ["advert", "commercial", "jingle", "station id", "sponsor", "promo", "http", "www.", ".com", ".net", ".org"]

    /// The song in an announced title, or `nil` if it doesn't name one.
    public init?(announced text: String, stationName: String?) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        guard !text.isEmpty, !Self.notSongs.contains(where: lowered.contains) else { return nil }
        if let stationName, LyricsMatching.normalize(stationName) == LyricsMatching.normalize(text) { return nil }
        var parts: (String, String)?
        for separator in Self.separators {
            if let range = text.range(of: separator) {
                parts = (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
                break
            }
        }
        if parts == nil, let range = text.range(of: " by ", options: [.caseInsensitive, .backwards]) {
            // "Title by Artist"
            parts = (String(text[range.upperBound...]), String(text[..<range.lowerBound]))
        }
        guard let (artist, title) = parts else { return nil }
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanArtist.isEmpty, !cleanTitle.isEmpty else { return nil }
        self.init(artist: cleanArtist, title: cleanTitle)
    }

    /// Whether `song` is this one: the same title (version notes like
    /// "(Remastered)" aside, accents and punctuation ignored) and the same
    /// artist (or one naming the other, for "feat." and duos). Stations that
    /// put the title first are matched too.
    public func matches(_ song: Song) -> Bool {
        Self.matches(song, artist: artist, title: title) || Self.matches(song, artist: title, title: artist)
    }

    private static func matches(_ song: Song, artist: String, title: String) -> Bool {
        guard LyricsMatching.normalize(LyricsMatching.cleanTitle(song.title)) == LyricsMatching.normalize(LyricsMatching.cleanTitle(title)),
              let songArtist = song.artist else { return false }
        let wanted = LyricsMatching.normalize(artist)
        let found = LyricsMatching.normalize(songArtist)
        guard !wanted.isEmpty, !found.isEmpty else { return false }
        return wanted == found || wanted.contains(found) || found.contains(wanted)
    }
}

/// Whether the song a station is playing is in the user's library: each time
/// the announced title changes, the server is searched for it (artist and
/// title, then the title alone) and the first song that matches is kept, for
/// Now Playing's "In Your Library". Only the user's server is asked. Each
/// title's answer is remembered for the session, so a station repeating a
/// song isn't searched again; a newer title always wins over a slow search
/// for an older one.
@MainActor
@Observable
public final class OnAirMatchModel {
    public typealias Search = @Sendable (String) async throws(SubsonicError) -> [Song]

    /// The song on air, if the station names one.
    public private(set) var onAir: OnAirSong?
    /// The library's copy of it, if there is one.
    public private(set) var match: Song?
    /// Whether the library is still being searched for the song on air, so
    /// "not in the library" isn't known yet.
    public private(set) var isSearching = false

    @ObservationIgnored private let search: Search
    @ObservationIgnored private var answers: [String: Song?] = [:]
    @ObservationIgnored private var latest: String?

    public init(search: @escaping Search) {
        self.search = search
    }

    /// Call with the station's announced title whenever it changes (`nil`
    /// when there's none, or for a song).
    public func update(announced: String?, stationName: String?) async {
        latest = announced
        let song = announced.flatMap { OnAirSong(announced: $0, stationName: stationName) }
        onAir = song
        guard let announced, let song else {
            match = nil
            isSearching = false
            return
        }
        if let known = answers[announced] {
            match = known
            isSearching = false
            return
        }
        match = nil
        isSearching = true
        let found = await find(song)
        // Another title came in meanwhile.
        guard latest == announced, !Task.isCancelled else { return }
        isSearching = false
        switch found {
        case .success(let song):
            answers[announced] = song
            match = song
        case .failure:
            // Not remembered: asked again if the title comes round again.
            match = nil
        }
    }

    /// The match (or none), or the search's failure.
    private func find(_ song: OnAirSong) async -> Result<Song?, SubsonicError> {
        for query in ["\(song.artist) \(song.title)", song.title, song.artist] {
            do {
                if let found = try await search(query).first(where: song.matches) { return .success(found) }
            } catch {
                return .failure(error)
            }
        }
        return .success(nil)
    }
}
