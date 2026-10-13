import Foundation
import Testing
@testable import NavidromeCore

struct TypesetMotionTests {
    private let frame: TimeInterval = 1.0 / 60
    private let silence = [Float](repeating: 0, count: 40)
    private let quiet = SpectrumEnergy(bass: 0, mid: 0, treble: 0)
    /// Five letters spread across the spectrum.
    private let positions = [0.0, 0.25, 0.5, 0.75, 0.99]

    private func run(
        _ motion: inout TypesetMotion, seconds: Double, levels: [Float]? = nil,
        energy: SpectrumEnergy? = nil, beat: Float = 0
    ) {
        for _ in 0..<Int((seconds * 60).rounded()) {
            motion.update(positions: positions, levels: levels ?? silence, energy: energy ?? quiet, beat: beat, elapsed: frame)
        }
    }

    @Test func softMusicFloatsGently() {
        var motion = TypesetMotion()
        let soft = [Float](repeating: 0.05, count: 40)
        // Past the small jump of the music starting.
        run(&motion, seconds: 3, levels: soft)
        var heights: [Double] = []
        for _ in 0..<300 {
            motion.update(positions: positions, levels: soft, energy: quiet, beat: 0, elapsed: frame)
            heights.append(motion.letters[0].dy)
        }
        #expect(motion.calm > 0.9)
        // It drifts up and down, but only a little.
        #expect((heights.max() ?? 0) - (heights.min() ?? 0) > 0.1)
        #expect(heights.allSatisfy { abs($0) < 0.2 })
    }

    @Test func loudMusicLosesTheCalm() {
        var motion = TypesetMotion()
        run(&motion, seconds: 10, levels: [Float](repeating: 0.5, count: 40))
        #expect(motion.calm < 0.1)
    }

    @Test func aLetterJumpsWhenItsBandGetsLouder() {
        var bass = silence
        for band in 0..<5 { bass[band] = 1 }
        var motion = TypesetMotion()
        var still = TypesetMotion()
        run(&motion, seconds: 2)
        run(&still, seconds: 2)
        run(&motion, seconds: 0.35, levels: bass)
        run(&still, seconds: 0.35)
        // Compared with no music, so the float cancels out.
        #expect(motion.letters[0].dy - still.letters[0].dy < -0.3)
        #expect(motion.letters[0].stretch > 1.15)
        #expect(motion.letters[0].brightness == 1)
        #expect(abs(motion.letters[4].dy - still.letters[4].dy) < 0.01)
        #expect(motion.letters[4].brightness == 0)
    }

    @Test func aSteadyLoudBandSettlesBackHome() {
        var bass = silence
        for band in 0..<5 { bass[band] = 1 }
        var motion = TypesetMotion()
        var still = TypesetMotion()
        run(&motion, seconds: 8, levels: bass)
        run(&still, seconds: 8)
        #expect(abs(motion.letters[0].dy - still.letters[0].dy) < 0.05)
    }

    @Test func aBassHitThumpsTheWholeTitle() {
        let bass = SpectrumEnergy(bass: 0.8, mid: 0, treble: 0)
        var motion = TypesetMotion()
        var still = TypesetMotion()
        run(&motion, seconds: 2)
        run(&still, seconds: 2)
        run(&motion, seconds: 0.3, energy: bass)
        run(&still, seconds: 0.3)
        // Compared with no bass, so the float cancels out: every letter lifts
        // together, without stretching.
        for (thumped, resting) in zip(motion.letters, still.letters) {
            #expect(resting.dy - thumped.dy > 0.2)
            #expect(abs(thumped.stretch - 1) < 0.01)
        }
        // A steady bass line lets the words settle back.
        run(&motion, seconds: 8, energy: bass)
        run(&still, seconds: 8)
        for (thumped, resting) in zip(motion.letters, still.letters) {
            #expect(abs(resting.dy - thumped.dy) < 0.05)
        }
    }

    @Test func trebleLeansTheTrebleEnd() {
        var motion = TypesetMotion()
        var still = TypesetMotion()
        run(&motion, seconds: 3, energy: SpectrumEnergy(bass: 0, mid: 0, treble: 0.6))
        run(&still, seconds: 3)
        // Compared with no treble, so the float's sway cancels out.
        #expect(motion.letters[4].rotation - still.letters[4].rotation > 0.15)
        #expect(abs(motion.letters[0].rotation - still.letters[0].rotation) < 0.01)
    }

    @Test func aDrumHitMakesTheLettersJumpOutAndThenSettle() {
        var calm = TypesetMotion()
        run(&calm, seconds: 1)
        var hit = calm
        let before = hit.letters
        run(&hit, seconds: 2.0 / 60, beat: 1)
        run(&hit, seconds: 0.12)
        run(&calm, seconds: 0.15)
        // Bigger, and mostly thrown upward.
        #expect(hit.letters.allSatisfy { $0.scale > 1.15 })
        #expect(zip(hit.letters, before).filter { $0.dy < $1.dy }.count >= 4)
        // Back where the music alone puts them.
        run(&hit, seconds: 4)
        run(&calm, seconds: 4)
        for (jumped, resting) in zip(hit.letters, calm.letters) {
            #expect(abs(jumped.dx - resting.dx) < 0.01)
            #expect(abs(jumped.dy - resting.dy) < 0.01)
            #expect(abs(jumped.rotation - resting.rotation) < 0.01)
            #expect(abs(jumped.scale - resting.scale) < 0.01)
        }
    }

    @Test func aHeldBeatJumpsOnce() {
        var held = TypesetMotion()
        run(&held, seconds: 0.3, beat: 1)
        var tapped = TypesetMotion()
        run(&tapped, seconds: 1.0 / 60, beat: 1)
        run(&tapped, seconds: 0.3 - 1.0 / 60)
        // Brightness follows the beat itself, so compare the movement.
        #expect(held.letters.map(\.dy) == tapped.letters.map(\.dy))
        #expect(held.letters.map(\.scale) == tapped.letters.map(\.scale))
    }

    @Test func newWordsStartAtRest() {
        var motion = TypesetMotion()
        run(&motion, seconds: 0.05, beat: 1)
        motion.update(positions: [0, 1], levels: silence, energy: quiet, beat: 0, elapsed: frame)
        #expect(motion.letters.count == 2)
        // Only the gentle float.
        #expect(motion.letters.allSatisfy { abs($0.dy) < 0.15 && abs($0.rotation) < 0.1 && abs($0.scale - 1) < 0.01 })
    }

    @Test func nearbyBandsAreAveraged() {
        #expect(TypesetMotion.level(at: 0.5, in: []) == 0)
        // Each clamped to 0...1 first.
        #expect(abs(TypesetMotion.level(at: 1, in: [0.2, 3]) - 0.6) < 0.001)
    }
}
