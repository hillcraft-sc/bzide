import Foundation

// Lyrics from the server. Navidrome reads them from the music files' tags and
// from .lrc files beside them.

extension SubsonicClient {
    /// The OpenSubsonic `songLyrics` extension's lyrics for a song, timed when
    /// the server has times. Only call this when the server advertises the
    /// extension. A song without lyrics gives an empty list.
    public func structuredLyrics(songID: String) async throws(SubsonicError) -> [StructuredLyrics] {
        struct Payload: Decodable {
            struct List: Decodable {
                let structuredLyrics: [StructuredLyrics]?
            }
            let lyricsList: List?
        }
        let payload = try await request("getLyricsBySongId", parameters: [.init(name: "id", value: songID)], as: Payload.self)
        return payload.lyricsList?.structuredLyrics ?? []
    }

    /// Classic Subsonic lyrics, found by artist and title: plain text with no
    /// timing. `nil` when the server has none.
    public func plainLyrics(artist: String?, title: String) async throws(SubsonicError) -> String? {
        struct Payload: Decodable {
            struct Body: Decodable {
                let value: String?
            }
            let lyrics: Body?
        }
        var parameters = [URLQueryItem(name: "title", value: title)]
        if let artist { parameters.append(.init(name: "artist", value: artist)) }
        let text = try await request("getLyrics", parameters: parameters, as: Payload.self).lyrics?.value
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

/// One set of lyrics from `getLyricsBySongId`. Decoded leniently: a line
/// without text is an empty line; one without a time makes the set unsynced.
public struct StructuredLyrics: Sendable, Equatable, Decodable {
    public struct Line: Sendable, Equatable {
        /// Milliseconds.
        public var start: Double?
        public var value: String
    }

    public var synced: Bool
    /// Milliseconds to shift every line by.
    public var offset: Double
    public var lines: [Line]

    public init(synced: Bool, offset: Double = 0, lines: [Line]) {
        self.synced = synced
        self.offset = offset
        self.lines = lines
    }

    private enum CodingKeys: String, CodingKey { case synced, offset, line }
    private enum LineKeys: String, CodingKey { case start, value }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offset = (try? c.decodeIfPresent(Double.self, forKey: .offset)) ?? 0
        var parsed: [Line] = []
        if var list = try? c.nestedUnkeyedContainer(forKey: .line) {
            while !list.isAtEnd {
                guard let line = try? list.nestedContainer(keyedBy: LineKeys.self) else {
                    _ = try? list.decode(EmptyLine.self)
                    continue
                }
                let start = (try? line.decodeIfPresent(Double.self, forKey: .start)) ?? nil
                let value = ((try? line.decodeIfPresent(String.self, forKey: .value)) ?? nil) ?? ""
                parsed.append(Line(start: start, value: value))
            }
        }
        lines = parsed
        let claimsSynced = (try? c.decodeIfPresent(Bool.self, forKey: .synced)) ?? nil
        synced = (claimsSynced ?? false) && !parsed.isEmpty && parsed.allSatisfy { $0.start != nil }
    }

    /// Skips an element that isn't a line object. Decoding it always
    /// succeeds, which moves the list on (a failed decode wouldn't).
    private struct EmptyLine: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    /// As lyrics to show: timed if synced (with any word times in the text),
    /// plain otherwise.
    public func lyrics(songDuration: TimeInterval?, source: Lyrics.Source) -> Lyrics {
        guard synced else {
            return Lyrics(plain: lines.map(\.value).joined(separator: "\n"), source: source)
        }
        let timed = lines.compactMap { line -> Lyrics.TimedLine? in
            guard let start = line.start else { return nil }
            let shift = offset / 1000
            let seconds = max(start / 1000 + shift, 0)
            // Word times in the text are shifted like the line.
            let (text, words) = LRC.wordTimes(in: line.value, lineStart: start / 1000)
            let shifted = words?.map { (text: $0.text, start: max($0.start + shift, 0)) }
            return Lyrics.TimedLine(start: seconds, text: text, words: shifted)
        }
        return Lyrics(timed: timed, songDuration: songDuration, source: source)
    }
}
