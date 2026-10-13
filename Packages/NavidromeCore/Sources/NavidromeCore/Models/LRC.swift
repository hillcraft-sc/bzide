import Foundation

/// Reads LRC, the common text format for synced lyrics:
///
///     [ar:Artist]
///     [offset:+250]
///     [00:12.30]First line
///     [00:15.80][01:02.10]A line sung twice
///     [00:19.00]<00:19.00>Enhanced <00:19.40>lines <00:19.90>time <00:20.30>words
///
/// Metadata tags are skipped except `offset` (milliseconds; positive shows the
/// lyrics earlier). Lines without a time are dropped.
public enum LRC {
    /// The timed lines, in order. Empty if the text has no timed lines.
    public static func parse(_ text: String) -> [Lyrics.TimedLine] {
        var offset: TimeInterval = 0
        var lines: [Lyrics.TimedLine] = []
        for rawLine in text.components(separatedBy: .newlines) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var starts: [TimeInterval] = []
            // Leading [..] tags: times, or metadata.
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = time(in: tag) {
                    starts.append(time)
                } else if tag.lowercased().hasPrefix("offset:") {
                    let value = tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)
                    offset = (Double(value) ?? 0) / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            guard !starts.isEmpty else { continue }
            for start in starts {
                let (text, words) = wordTimes(in: String(rest), lineStart: start)
                lines.append(Lyrics.TimedLine(start: start, text: text, words: words))
            }
        }
        // Applied after reading, since the offset tag can come anywhere.
        return lines
            .map { line in
                var shifted = line
                shifted.start = max(line.start - offset, 0)
                shifted.words = line.words?.map { ($0.text, max($0.start - offset, 0)) }
                return shifted
            }
            .sorted { $0.start < $1.start }
    }

    /// A line's text without `<mm:ss.xx>` word times, and the words with their
    /// times if it had any. Text before the first time starts with the line.
    public static func wordTimes(in text: String, lineStart: TimeInterval) -> (text: String, words: [(text: String, start: TimeInterval)]?) {
        guard text.contains("<") else { return (text.trimmingCharacters(in: .whitespaces), nil) }
        var words: [(text: String, start: TimeInterval)] = []
        var plain = ""
        var current = lineStart
        var foundTime = false
        var pending = ""
        var rest = Substring(text)
        func flush() {
            for piece in pending.split(whereSeparator: \.isWhitespace) {
                words.append((String(piece), current))
            }
            pending = ""
        }
        while let open = rest.firstIndex(of: "<") {
            guard let close = rest[open...].firstIndex(of: ">"), let time = time(in: rest[rest.index(after: open)..<close]) else {
                // Not a time: keep the "<" as text.
                pending += rest[...open]
                plain += rest[...open]
                rest = rest[rest.index(after: open)...]
                continue
            }
            pending += rest[..<open]
            plain += rest[..<open]
            flush()
            current = time
            foundTime = true
            rest = rest[rest.index(after: close)...]
        }
        pending += rest
        plain += rest
        flush()
        let cleaned = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Without a single real time, these aren't word times.
        return (cleaned, foundTime && !words.isEmpty ? words : nil)
    }

    /// `mm:ss`, `mm:ss.xx` or `mm:ss:xx` as seconds; `nil` if it isn't a time.
    static func time(in tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, let minutes = Int(parts[0]), minutes >= 0 else { return nil }
        let secondsText = parts.count == 3 ? "\(parts[1]).\(parts[2])" : String(parts[1])
        guard let seconds = Double(secondsText), seconds >= 0, seconds < 60 else { return nil }
        return Double(minutes) * 60 + seconds
    }
}
