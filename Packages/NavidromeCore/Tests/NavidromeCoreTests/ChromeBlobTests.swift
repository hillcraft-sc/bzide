import Foundation
import Testing
@testable import NavidromeCore

struct ChromeBlobTests {
    private let silence = [Float](repeating: 0, count: 40)
    private let count = ChromeBlob.pointCount
    /// Indexes of the points at 6, 12, 3 and 9 o'clock (y down: 6 o'clock is a quarter turn).
    private var bottom: Int { count / 4 }
    private var top: Int { count * 3 / 4 }
    private var right: Int { 0 }
    private var left: Int { count / 2 }

    @Test func silenceIsNearlyRound() {
        let radii = ChromeBlob.radii(levels: silence, beat: 0, time: 12)
        #expect(radii.count == count)
        #expect(radii.allSatisfy { abs($0 - 1) < 0.05 })
    }

    @Test func bassBulgesAtTheBottomAndTrebleAtTheTop() {
        var bass = silence
        bass[0] = 1
        bass[1] = 1
        var treble = silence
        treble[38] = 1
        treble[39] = 1
        let low = ChromeBlob.radii(levels: bass, beat: 0, time: 0)
        let high = ChromeBlob.radii(levels: treble, beat: 0, time: 0)
        #expect(low[bottom] > low[top] + 0.05)
        #expect(high[top] > high[bottom] + 0.05)
    }

    @Test func itsMirroredLeftAndRight() {
        let levels: [Float] = (0..<40).map { Float($0 % 7) / 7 }
        let radii = ChromeBlob.radii(levels: levels, beat: 0, time: 0)
        // Without the wobble (time 0 still has some), compare the pushes: the
        // same height on each side gets the same bulge.
        let flat = ChromeBlob.radii(levels: silence, beat: 0, time: 0)
        for offset in 1..<(count / 4) {
            let rightSide = radii[bottom - offset] - flat[bottom - offset]
            let leftSide = radii[bottom + offset] - flat[bottom + offset]
            #expect(abs(rightSide - leftSide) < 0.001)
        }
    }

    @Test func loudMusicStaysInBounds() {
        let loud = [Float](repeating: 3, count: 40)
        let radii = ChromeBlob.radii(levels: loud, beat: 1, time: 0)
        // Resting radius times at most 1 + 0.4 + 0.08 + wobble.
        #expect(radii.allSatisfy { $0 > 1 && $0 < 1.55 })
    }

    @Test func aBeatSwellsItAllAtOnce() {
        let still = ChromeBlob.radii(levels: silence, beat: 0, time: 3)
        let hit = ChromeBlob.radii(levels: silence, beat: 1, time: 3)
        #expect(zip(still, hit).allSatisfy { abs(($1 - $0) - 0.08) < 0.001 })
    }

    @Test func noLevelsIsJustTheWobble() {
        let radii = ChromeBlob.radii(levels: [], beat: 0, time: 5)
        #expect(radii.count == count)
        #expect(radii.allSatisfy { abs($0 - 1) < 0.05 })
    }
}
