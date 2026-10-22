import Foundation

/// A song's lyrics, ready to show. Synced lyrics have a start time for each
/// line and a time span for each word; unsynced lyrics are just lines of text.
///
/// Word times come from the lyrics when they have them (enhanced LRC). When
/// they don't, they're estimated: the line's words are spread over the time
/// until the next line, longer words taking longer, finishing a little early
/// the way a singer breathes before the next line, and never stretched over a
/// long instrumental gap.
public struct Lyrics: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// The user's own server.
        case server
        /// LRCLIB, the online lyrics database.
        case lrclib
    }

    public struct Word: Sendable, Equatable {
        public var text: String
        public var start: TimeInterval
        public var end: TimeInterval
    }

    public struct Line: Sendable, Equatable, Identifiable {
        /// Its place in the lyrics, from 0.
        public var id: Int
        /// When it's sung; `nil` in unsynced lyrics.
        public var start: TimeInterval?
        public var text: String
        /// Each word's time; empty in unsynced lyrics and for breaks.
        public var words: [Word]
        /// Whether the word times came with the lyrics rather than being estimated.
        public var hasExactWordTimes: Bool

        /// An empty line: an instrumental break.
        public var isBreak: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public var lines: [Line]
    public var source: Source
    /// LRCLIB's id for these lyrics, when they came from there.
    public var lrclibID: Int?

    public var isSynced: Bool { lines.contains { $0.start != nil } }

    /// Lines of text with no timing.
    public init(plain text: String, source: Source) {
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let trimmed = raw.map { $0.trimmingCharacters(in: .whitespaces) }
        // Drop blank lines at either end; blank lines inside separate verses.
        let first = trimmed.firstIndex { !$0.isEmpty } ?? trimmed.endIndex
        let last = trimmed.lastIndex { !$0.isEmpty } ?? trimmed.startIndex
        let kept = first <= last ? Array(trimmed[first...last]) : []
        lines = kept.enumerated().map { index, text in
            Line(id: index, start: nil, text: text, words: [], hasExactWordTimes: false)
        }
        self.source = source
    }

    /// Timed lines, in any order. `songDuration` bounds the last line.
    public init(timed: [TimedLine], songDuration: TimeInterval?, source: Source) {
        let sorted = timed.sorted { $0.start < $1.start }
        lines = sorted.enumerated().map { index, line in
            let next = index + 1 < sorted.count ? sorted[index + 1].start : nil
            let end = next ?? max(songDuration ?? (line.start + Self.lastLineLength), line.start + 0.5)
            let text = line.text.trimmingCharacters(in: .whitespaces)
            let words: [Word]
            if let exact = line.words, !exact.isEmpty {
                words = Self.exactWords(exact, lineEnd: end)
            } else {
                words = Self.estimatedWords(in: text, from: line.start, until: end)
            }
            return Line(id: index, start: line.start, text: text, words: words, hasExactWordTimes: !(line.words ?? []).isEmpty)
        }
        self.source = source
    }

    /// A line with its start time and, if the lyrics have them, its words' start times.
    public struct TimedLine: Sendable, Equatable {
        public var start: TimeInterval
        public var text: String
        public var words: [(text: String, start: TimeInterval)]?

        public init(start: TimeInterval, text: String, words: [(text: String, start: TimeInterval)]? = nil) {
            self.start = start
            self.text = text
            self.words = words
        }

        public static func == (lhs: TimedLine, rhs: TimedLine) -> Bool {
            lhs.start == rhs.start && lhs.text == rhs.text
                && lhs.words?.map(\.text) == rhs.words?.map(\.text)
                && lhs.words?.map(\.start) == rhs.words?.map(\.start)
        }
    }

    // MARK: - Following along

    /// Lines show a moment early, so the eye gets there as the voice does.
    static let lead: TimeInterval = 0.15

    /// The line being sung at `time`: the last one that has started. `nil`
    /// before the first line, and always in unsynced lyrics.
    public func lineIndex(at time: TimeInterval) -> Int? {
        lines.lastIndex { line in
            guard let start = line.start else { return false }
            return start <= time + Self.lead
        }
    }

    /// How much of a word has been sung at `time`, 0...1.
    public static func progress(of word: Word, at time: TimeInterval) -> Double {
        guard word.end > word.start else { return time >= word.start ? 1 : 0 }
        return min(max((time - word.start) / (word.end - word.start), 0), 1)
    }

    // MARK: - Word timing

    /// A line with nothing after it lasts this long.
    static let lastLineLength: TimeInterval = 6
    /// About how long a syllable takes to sing, and the most a line's words
    /// may take beyond that, so a line before a long break isn't stretched out.
    static let syllableTime: TimeInterval = 0.32
    static let lineSlack: TimeInterval = 0.6
    /// The share of the gap to the next line that the words may use.
    static let gapShare = 0.9
    /// The longest a last timed word may be held.
    static let longestWord: TimeInterval = 1.5

    static func exactWords(_ words: [(text: String, start: TimeInterval)], lineEnd: TimeInterval) -> [Word] {
        words.enumerated().compactMap { index, word in
            let text = word.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            let next = index + 1 < words.count ? words[index + 1].start : min(lineEnd, word.start + longestWord)
            return Word(text: text, start: word.start, end: max(next, word.start))
        }
    }

    static func estimatedWords(in text: String, from start: TimeInterval, until end: TimeInterval) -> [Word] {
        let pieces = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !pieces.isEmpty else { return [] }
        let syllables = pieces.map { Double(syllableCount($0)) }
        let total = syllables.reduce(0, +)
        let gap = max(end - start, 0.2)
        let span = min(gap * gapShare, total * syllableTime + lineSlack)
        var time = start
        return zip(pieces, syllables).map { piece, count in
            let length = span * count / total
            defer { time += length }
            return Word(text: piece, start: time, end: time + length)
        }
    }

    /// Roughly how many syllables a word has: its groups of vowels, at least one.
    static func syllableCount(_ word: String) -> Int {
        let vowels = Set("aeiouyàáâäãåèéêëìíîïòóôöõùúûüýæøœ")
        var count = 0
        var inVowels = false
        for character in word.lowercased() {
            let isVowel = vowels.contains(character)
            if isVowel && !inVowels { count += 1 }
            inVowels = isVowel
        }
        // A silent final "e", as in "time" or "love".
        if count > 1, word.lowercased().hasSuffix("e"), !word.lowercased().hasSuffix("le") {
            count -= 1
        }
        return max(count, 1)
    }
}
