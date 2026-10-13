import Foundation
import Testing
@testable import NavidromeCore

struct LyricsTimingTests {
    private func lyrics(_ timed: [Lyrics.TimedLine], duration: TimeInterval? = 200) -> Lyrics {
        Lyrics(timed: timed, songDuration: duration, source: .server)
    }

    @Test func estimatedWordsFillTheLineInOrder() {
        let line = lyrics([.init(start: 10, text: "Wake up to the morning static"), .init(start: 14, text: "Next")]).lines[0]
        #expect(line.words.map(\.text) == ["Wake", "up", "to", "the", "morning", "static"])
        #expect(line.words.first?.start == 10)
        // Each word starts as the one before it ends.
        for (word, next) in zip(line.words, line.words.dropFirst()) {
            #expect(abs(word.end - next.start) < 0.0001)
        }
        // Finished before the next line, leaving a breath.
        #expect((line.words.last?.end ?? 0) <= 14 - 0.3)
        #expect(!line.hasExactWordTimes)
    }

    @Test func longerWordsTakeLonger() {
        let line = lyrics([.init(start: 0, text: "I remember everything"), .init(start: 4, text: "Next")]).lines[0]
        let lengths = line.words.map { $0.end - $0.start }
        #expect(lengths[2] > lengths[1])
        #expect(lengths[1] > lengths[0])
    }

    @Test func aLineBeforeALongBreakIsntStretched() {
        let line = lyrics([.init(start: 0, text: "Short line here"), .init(start: 60, text: "After the solo")]).lines[0]
        #expect((line.words.last?.end ?? 0) < 3)
    }

    @Test func exactWordTimesAreKept() {
        let timed = Lyrics.TimedLine(start: 16, text: "Coffee going cold", words: [("Coffee", 16), ("going", 16.6), ("cold", 17.1)])
        let line = lyrics([timed, .init(start: 30, text: "Later")]).lines[0]
        #expect(line.hasExactWordTimes)
        #expect(line.words.map(\.start) == [16, 16.6, 17.1])
        #expect(line.words.map(\.end).prefix(2) == [16.6, 17.1])
        // The last word is held no longer than a long note.
        #expect(line.words.last?.end == 17.1 + Lyrics.longestWord)
    }

    @Test func theLastLineEndsWithTheSong() {
        let line = lyrics([.init(start: 190, text: "The very last line")], duration: 200).lines[0]
        #expect((line.words.last?.end ?? 0) <= 200)
    }

    @Test func emptyLinesAreBreaks() {
        let lines = lyrics([.init(start: 0, text: "Words"), .init(start: 5, text: "  "), .init(start: 20, text: "More")]).lines
        #expect(lines[1].isBreak)
        #expect(lines[1].words.isEmpty)
        #expect(!lines[0].isBreak)
    }

    @Test func theCurrentLineIsTheLastToHaveStarted() {
        let song = lyrics([.init(start: 10, text: "One"), .init(start: 20, text: "Two"), .init(start: 30, text: "Three")])
        #expect(song.lineIndex(at: 5) == nil)
        #expect(song.lineIndex(at: 10) == 0)
        #expect(song.lineIndex(at: 25) == 1)
        // Shown a moment early.
        #expect(song.lineIndex(at: 30 - Lyrics.lead / 2) == 2)
        #expect(song.lineIndex(at: 500) == 2)
    }

    @Test func aWordFillsAsItsSung() {
        let word = Lyrics.Word(text: "cold", start: 10, end: 12)
        #expect(Lyrics.progress(of: word, at: 9) == 0)
        #expect(Lyrics.progress(of: word, at: 11) == 0.5)
        #expect(Lyrics.progress(of: word, at: 13) == 1)
    }

    @Test func plainLyricsKeepVersesButTrimTheEnds() {
        let plain = Lyrics(plain: "\n\nFirst line\r\nSecond line\n\nNew verse\n\n", source: .server)
        #expect(plain.lines.map(\.text) == ["First line", "Second line", "", "New verse"])
        #expect(!plain.isSynced)
        #expect(plain.lineIndex(at: 100) == nil)
    }

    @Test func countsSyllablesRoughly() {
        #expect(Lyrics.syllableCount("I") == 1)
        #expect(Lyrics.syllableCount("time") == 1)
        #expect(Lyrics.syllableCount("morning") == 2)
        #expect(Lyrics.syllableCount("beautiful") == 3)
        #expect(Lyrics.syllableCount("hmm") == 1)
    }
}
