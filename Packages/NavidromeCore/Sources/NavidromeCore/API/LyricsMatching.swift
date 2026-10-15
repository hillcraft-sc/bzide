import Foundation

/// How Bzide tells whether lyrics found on LRCLIB are for the same recording
/// as the song playing. Titles often carry a version note that LRCLIB's don't
/// ("(2025 Remaster)", "- Single Version", "[Explicit]", "feat. …"), and
/// names differ in accents and punctuation ("Motley Crue" and "Mötley Crüe").
/// Notes that mean a different performance ("Live", "Acoustic", "Demo"…) are
/// kept and must match, since that recording's lyrics are timed differently.
public enum LyricsMatching {
    /// Words in a version note that don't change the recording.
    static let sameRecordingWords = [
        "remaster", "remastered", "deluxe", "version", "edit", "explicit", "clean", "mono", "stereo",
        "bonus", "single", "radio", "anniversary", "expanded", "edition", "feat", "ft", "featuring", "with",
    ]

    /// Words that mean a different performance.
    static let otherRecordingWords = ["live", "acoustic", "unplugged", "demo", "instrumental", "remix", "orchestral"]

    /// The title without notes that don't change the recording, e.g.
    /// "My Evil Ways (2025 Remaster)" → "My Evil Ways",
    /// "Song - Single Version" → "Song", "Song (feat. Someone)" → "Song".
    /// A note naming a different performance ("(Live)") is kept.
    public static func cleanTitle(_ title: String) -> String {
        var text = title
        // Bracketed notes: ( ) and [ ].
        for (open, close) in [("(", ")"), ("[", "]")] {
            var result = ""
            var rest = Substring(text)
            while let start = rest.firstIndex(of: Character(open)), let end = rest[start...].firstIndex(of: Character(close)) {
                let note = rest[rest.index(after: start)..<end]
                result += rest[..<start]
                if !isSameRecordingNote(String(note)) {
                    result += rest[start...end]
                }
                rest = rest[rest.index(after: end)...]
            }
            text = result + rest
        }
        // A " - note" at the end.
        if let dash = text.range(of: " - ", options: .backwards), isSameRecordingNote(String(text[dash.upperBound...])) {
            text = String(text[..<dash.lowerBound])
        }
        // "feat. Someone" outside brackets.
        for marker in [" feat. ", " ft. ", " featuring "] {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                text = String(text[..<range.lowerBound])
            }
        }
        let cleaned = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned.isEmpty ? title : cleaned
    }

    /// Lowercased, without accents or punctuation, "&" as "and", for comparing names.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "&", with: " and ")
        let letters = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    /// Which different-performance words a title or album mentions.
    static func performanceMarks(_ text: String) -> Set<String> {
        let words = Set(normalize(text).split(separator: " ").map(String.init))
        return Set(otherRecordingWords.filter(words.contains))
    }

    private static func isSameRecordingNote(_ note: String) -> Bool {
        let words = normalize(note).split(separator: " ").map(String.init)
        guard !words.isEmpty, performanceMarks(note).isEmpty else { return false }
        // Any version word, or just a year ("(2011)").
        return words.contains(where: sameRecordingWords.contains)
            || (words.count == 1 && words[0].count == 4 && Int(words[0]) != nil)
    }

    /// What's known about a found set of lyrics, to compare with the song.
    public struct Candidate: Equatable, Sendable {
        public var title: String?
        public var artist: String?
        public var album: String?
        /// Seconds.
        public var duration: Double?
        public var isSynced: Bool
    }

    /// The song being matched.
    public struct Song: Equatable, Sendable {
        public var title: String
        public var artist: String?
        public var album: String?
        /// Seconds.
        public var duration: Int?
    }

    /// The longest a match may differ in length, in seconds.
    public static let durationTolerance: Double = 2

    /// How good a match a candidate is, or `nil` if it's for something else:
    /// a different length (more than 2 s off), title, artist or performance.
    /// Names the candidate doesn't give aren't held against it.
    public static func score(_ candidate: Candidate, for song: Song) -> Double? {
        var score = 10.0
        if let duration = song.duration, let length = candidate.duration {
            let difference = abs(length - Double(duration))
            guard difference <= durationTolerance else { return nil }
            score -= difference * 2
        }
        let songTitle = normalize(cleanTitle(song.title))
        if let title = candidate.title {
            let candidateTitle = normalize(cleanTitle(title))
            guard candidateTitle == songTitle else { return nil }
        }
        if let artist = song.artist, let candidateArtist = candidate.artist {
            let wanted = normalize(artist)
            let found = normalize(candidateArtist)
            guard wanted == found || wanted.contains(found) || found.contains(wanted) else { return nil }
        }
        // A live (or acoustic…) song needs that performance's lyrics, and the other way round.
        let songMarks = performanceMarks(song.title + " " + (song.album ?? ""))
        let candidateMarks = performanceMarks((candidate.title ?? "") + " " + (candidate.album ?? ""))
        if candidate.title != nil || candidate.album != nil {
            guard songMarks == candidateMarks else { return nil }
        }
        if let album = song.album, let candidateAlbum = candidate.album, normalize(album) == normalize(candidateAlbum) {
            score += 3
        }
        if candidate.isSynced { score += 2 }
        return score
    }
}
