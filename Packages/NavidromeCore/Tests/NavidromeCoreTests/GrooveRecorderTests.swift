import Foundation
import Testing
@testable import NavidromeCore

struct GrooveRecorderTests {
    private let song = UUID()
    private let frame: TimeInterval = 1.0 / 60

    /// The engine's position at a frame: it only updates every half second.
    private func reported(_ frameIndex: Int) -> TimeInterval {
        (Double(frameIndex) / 60 * 2).rounded(.down) / 2
    }

    @Test func recordsHowLoudEachMomentWas() {
        var groove = GrooveRecorder()
        // One second at a level of 0.5, the engine reporting its position twice a second.
        for index in 0..<60 {
            groove.update(entryID: song, position: reported(index), isPlaying: true, level: 0.5, elapsed: frame)
        }
        #expect(abs(groove.songTime - 1) < 0.01)
        let heard = groove.levels.compactMap { $0 }
        #expect(heard.count >= GrooveRecorder.samplesPerSecond - 1)
        #expect(heard.allSatisfy { $0 == 0.5 })
    }

    @Test func momentsBeforeOpeningAreUnknown() {
        var groove = GrooveRecorder()
        // Opened 3 seconds into the song.
        groove.update(entryID: song, position: 3, isPlaying: true, level: 0.8, elapsed: frame)
        #expect(groove.levels.count == 3 * GrooveRecorder.samplesPerSecond + 1)
        #expect(groove.levels.prefix(3 * GrooveRecorder.samplesPerSecond).allSatisfy { $0 == nil })
        #expect(groove.levels.last == 0.8)
    }

    @Test func pausedTimeDoesNotMoveOrRecord() {
        var groove = GrooveRecorder()
        groove.update(entryID: song, position: 1, isPlaying: true, level: 0.3, elapsed: frame)
        let before = groove
        for _ in 0..<30 {
            groove.update(entryID: song, position: 1, isPlaying: false, level: 0.9, elapsed: frame)
        }
        #expect(groove.songTime == before.songTime)
        #expect(groove.levels == before.levels)
    }

    @Test func aSeekMovesTheStylusAndKeepsWhatWasCut() {
        var groove = GrooveRecorder()
        for index in 0..<60 {
            groove.update(entryID: song, position: reported(index), isPlaying: true, level: 0.4, elapsed: frame)
        }
        groove.update(entryID: song, position: 30, isPlaying: true, level: 0.6, elapsed: frame)
        #expect(abs(groove.songTime - 30) < 0.01)
        #expect(groove.levels[5] == 0.4)
        #expect(groove.levels[30 * GrooveRecorder.samplesPerSecond] == 0.6)
    }

    @Test func aNewSongStartsABlankRecord() {
        var groove = GrooveRecorder()
        for _ in 0..<60 {
            groove.update(entryID: song, position: 0, isPlaying: true, level: 0.4, elapsed: frame)
        }
        groove.update(entryID: UUID(), position: 0, isPlaying: true, level: 0.2, elapsed: 0)
        #expect(groove.levels == [0.2])
        #expect(groove.songTime == 0)
    }

    @Test func levelsAreKeptInRange() {
        var groove = GrooveRecorder()
        groove.update(entryID: song, position: 0, isPlaying: true, level: 3, elapsed: 0)
        #expect(groove.levels == [1])
    }
}
