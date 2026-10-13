import Testing
@testable import NavidromeCore

struct LivingCoverTests {
    private let quiet = SpectrumEnergy(bass: 0, mid: 0, treble: 0)
    private let silence = [Float](repeating: 0, count: 40)

    @Test func silenceLeavesTheCoverWhole() {
        for row in 0..<LivingCover.gridSize {
            for column in 0..<LivingCover.gridSize {
                #expect(LivingCover.motion(row: row, column: column, levels: silence, energy: quiet, beat: 0) == .still)
            }
        }
    }

    @Test func bassPushesTilesOutFromTheCenter() {
        let bass = SpectrumEnergy(bass: 1, mid: 0, treble: 0)
        let topLeft = LivingCover.motion(row: 0, column: 0, levels: silence, energy: bass, beat: 0)
        let bottomRight = LivingCover.motion(row: 7, column: 7, levels: silence, energy: bass, beat: 0)
        let nearCenter = LivingCover.motion(row: 3, column: 4, levels: silence, energy: bass, beat: 0)
        #expect(topLeft.dx < 0 && topLeft.dy < 0)
        #expect(bottomRight.dx > 0 && bottomRight.dy > 0)
        // Outer tiles travel further than inner ones.
        #expect(abs(topLeft.dx) > abs(nearCenter.dx))
    }

    @Test func aBeatAddsABurst() {
        let still = LivingCover.motion(row: 0, column: 0, levels: silence, energy: quiet, beat: 0)
        let hit = LivingCover.motion(row: 0, column: 0, levels: silence, energy: quiet, beat: 1)
        #expect(hit.dx < still.dx)
        #expect(hit.scale > still.scale)
    }

    @Test func midsTiltNeighborsOppositeWays() {
        let mids = SpectrumEnergy(bass: 0, mid: 1, treble: 0)
        let a = LivingCover.motion(row: 2, column: 2, levels: silence, energy: mids, beat: 0)
        let b = LivingCover.motion(row: 2, column: 3, levels: silence, energy: mids, beat: 0)
        #expect(a.rotation > 0)
        #expect(b.rotation < 0)
    }

    @Test func eachTileFollowsItsOwnBand() {
        // Only the bass bands are loud: the middle tiles lift, the corners don't.
        var levels = silence
        for band in 0..<8 { levels[band] = 1 }
        let middle = LivingCover.motion(row: 3, column: 3, levels: levels, energy: quiet, beat: 0)
        let corner = LivingCover.motion(row: 0, column: 0, levels: levels, energy: quiet, beat: 0)
        #expect(middle.scale > 1)
        #expect(corner.scale == 1)
    }

    @Test func trebleMakesTheEdgesSparkle() {
        let treble = SpectrumEnergy(bass: 0, mid: 0, treble: 1)
        let motion = LivingCover.motion(row: 1, column: 1, levels: silence, energy: treble, beat: 0)
        #expect(motion.sparkle > 0)
        #expect(motion.sparkle <= 1)
    }
}
