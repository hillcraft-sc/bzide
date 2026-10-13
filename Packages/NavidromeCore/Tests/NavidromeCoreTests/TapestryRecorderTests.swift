import Foundation
import Testing
@testable import NavidromeCore

struct TapestryRecorderTests {
    private let song = UUID()
    private let frame: TimeInterval = 1.0 / 60
    private let quiet = [Float](repeating: 0.2, count: 40)

    @Test func weavesTwoRowsASecond() {
        var tapestry = TapestryRecorder()
        // Two seconds at 60 frames a second, the engine reporting every half second.
        for index in 0..<120 {
            let position = (Double(index) / 60 * 2).rounded(.down) / 2
            tapestry.update(entryID: song, position: position, isPlaying: true, levels: quiet, elapsed: frame)
        }
        #expect(tapestry.rows.count == 4 || tapestry.rows.count == 5)
        let woven = tapestry.rows.compactMap { $0 }
        #expect(woven.count == tapestry.rows.count)
        #expect(woven.allSatisfy { $0.count == TapestryRecorder.threadCount })
    }

    @Test func eachThreadKeepsTheLoudestMomentOfItsRow() {
        var tapestry = TapestryRecorder()
        var loudBass = quiet
        loudBass[0] = 1
        loudBass[1] = 1
        tapestry.update(entryID: song, position: 0, isPlaying: true, levels: quiet, elapsed: 0)
        tapestry.update(entryID: song, position: 0, isPlaying: true, levels: loudBass, elapsed: frame)
        tapestry.update(entryID: song, position: 0, isPlaying: true, levels: quiet, elapsed: frame)
        let row = tapestry.rows.first ?? nil
        #expect(tapestry.rows.count == 1)
        #expect(row?.first == 1)
        #expect(row?.last == 0.2)
    }

    @Test func rowsBeforeOpeningAreUnknown() {
        var tapestry = TapestryRecorder()
        // Opened 3 seconds into the song.
        tapestry.update(entryID: song, position: 3, isPlaying: true, levels: quiet, elapsed: frame)
        #expect(tapestry.rows.count == 3 * TapestryRecorder.rowsPerSecond + 1)
        #expect(tapestry.rows.dropLast().allSatisfy { $0 == nil })
        #expect(tapestry.rows.last != nil)
    }

    @Test func pausedTimeDoesNotWeave() {
        var tapestry = TapestryRecorder()
        tapestry.update(entryID: song, position: 1, isPlaying: true, levels: quiet, elapsed: frame)
        let before = tapestry.rows
        for _ in 0..<60 {
            tapestry.update(entryID: song, position: 1, isPlaying: false, levels: quiet.map { _ in 1 }, elapsed: frame)
        }
        #expect(tapestry.rows == before)
    }

    @Test func aSeekKeepsWhatWasWoven() {
        var tapestry = TapestryRecorder()
        tapestry.update(entryID: song, position: 0, isPlaying: true, levels: quiet, elapsed: 0)
        tapestry.update(entryID: song, position: 30, isPlaying: true, levels: quiet, elapsed: frame)
        #expect(abs(tapestry.songTime - 30) < 0.01)
        #expect(tapestry.rows.first != nil)
        #expect(tapestry.rows[30 * TapestryRecorder.rowsPerSecond] != nil)
    }

    @Test func aNewSongStartsFreshCloth() {
        var tapestry = TapestryRecorder()
        tapestry.update(entryID: song, position: 10, isPlaying: true, levels: quiet, elapsed: 0)
        tapestry.update(entryID: UUID(), position: 0, isPlaying: true, levels: quiet, elapsed: 0)
        #expect(tapestry.rows.count == 1)
        #expect(tapestry.songTime == 0)
    }

    @Test func bandsAreGroupedIntoThreadsAndClamped() {
        let bands: [Float] = (0..<40).map { $0 < 2 ? 3 : -1 }
        let threads = TapestryRecorder.threads(from: bands)
        #expect(threads.count == TapestryRecorder.threadCount)
        #expect(threads.first == 1)
        #expect(threads.dropFirst().allSatisfy { $0 == 0 })
        // Fewer bands than threads still gives every thread a value.
        #expect(TapestryRecorder.threads(from: [0.5, 0.7]).count == TapestryRecorder.threadCount)
        #expect(TapestryRecorder.threads(from: []).allSatisfy { $0 == 0 })
    }
}
