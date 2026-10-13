import Foundation
import Testing
@testable import NavidromeCore

struct LRCTests {
    @Test func readsTimedLinesInOrder() {
        let lines = LRC.parse("""
        [ar:The Placeholders]
        [ti:Morning Static]
        [00:16.00]Coffee going cold again
        [00:12.50]Wake up to the morning static
        Not timed, so dropped
        """)
        #expect(lines.map(\.start) == [12.5, 16])
        #expect(lines.map(\.text) == ["Wake up to the morning static", "Coffee going cold again"])
        #expect(lines.allSatisfy { $0.words == nil })
    }

    @Test func aLineWithSeveralTimesIsSungEachTime() {
        let lines = LRC.parse("[00:10.00][01:20.00]Chorus line\n[00:40.00]Verse")
        #expect(lines.map(\.start) == [10, 40, 80])
        #expect(lines.map(\.text) == ["Chorus line", "Verse", "Chorus line"])
    }

    @Test func theOffsetShiftsEveryLine() {
        // Positive shows lyrics earlier.
        let lines = LRC.parse("[00:10.00]First\n[offset:+500]\n[00:20.00]Second")
        #expect(lines.map(\.start) == [9.5, 19.5])
    }

    @Test func readsTheTimeFormats() {
        #expect(LRC.time(in: "01:02.50") == 62.5)
        #expect(LRC.time(in: "01:02:50") == 62.5)
        #expect(LRC.time(in: "01:02") == 62)
        #expect(LRC.time(in: "ar:Someone") == nil)
        #expect(LRC.time(in: "00:75.00") == nil)
    }

    @Test func readsEnhancedWordTimes() {
        let lines = LRC.parse("[00:16.00]<00:16.00>Coffee <00:16.60>going <00:17.10>cold <00:17.50>again")
        let line = lines.first
        #expect(line?.text == "Coffee going cold again")
        #expect(line?.words?.map(\.text) == ["Coffee", "going", "cold", "again"])
        #expect(line?.words?.map(\.start) == [16, 16.6, 17.1, 17.5])
    }

    @Test func wordsBeforeTheFirstWordTimeStartWithTheLine() {
        let (text, words) = LRC.wordTimes(in: "Hey <00:05.00>you", lineStart: 4)
        #expect(text == "Hey you")
        #expect(words?.map(\.start) == [4, 5])
    }

    @Test func angleBracketsThatArentTimesStayText() {
        let (text, words) = LRC.wordTimes(in: "I <3 you", lineStart: 0)
        #expect(text == "I <3 you")
        #expect(words == nil)
    }

    @Test func textWithNoTimesHasNoLines() {
        #expect(LRC.parse("Just some words\nand more words").isEmpty)
    }
}
