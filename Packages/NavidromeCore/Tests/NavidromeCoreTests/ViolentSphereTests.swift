import Foundation
import simd
import Testing
@testable import NavidromeCore

struct ViolentSphereTests {
    private let frame: TimeInterval = 1.0 / 60

    private func run(_ sphere: inout ViolentSphere, seconds: Double, levels: [Float], beat: Float = 0) {
        for _ in 0..<Int(seconds * 60) {
            sphere.update(levels: levels, beat: beat, elapsed: frame)
        }
    }

    private func average(_ radii: [Float]) -> Float {
        radii.reduce(0, +) / Float(radii.count)
    }

    @Test func theMeshIsAGeodesicSphere() {
        // An icosahedron, then each triangle split in four.
        #expect(ViolentSphere(subdivisions: 0).directions.count == 12)
        let once = ViolentSphere(subdivisions: 1)
        #expect(once.directions.count == 42)
        #expect(once.triangles.count == 80 * 3)
        #expect(once.edges.count == 120 * 2)
        #expect(once.directions.allSatisfy { abs(simd_length($0) - 1) < 0.0001 })
    }

    @Test func silenceIsACalmRoughBall() {
        var sphere = ViolentSphere(subdivisions: 2)
        run(&sphere, seconds: 1, levels: [Float](repeating: 0, count: 40))
        #expect(sphere.radii.allSatisfy { $0 >= 1 && $0 <= 1.1 })
    }

    @Test func loudMusicPushesSpikesOutWithinTheLimit() {
        var quiet = ViolentSphere(subdivisions: 2)
        var loud = ViolentSphere(subdivisions: 2)
        run(&quiet, seconds: 1, levels: [Float](repeating: 0.1, count: 40))
        run(&loud, seconds: 1, levels: [Float](repeating: 1, count: 40))
        #expect(average(loud.radii) > average(quiet.radii) + 0.2)
        #expect(loud.radii.allSatisfy { $0 <= ViolentSphere.maxRadius })
    }

    @Test func eachSliceOfTheSpectrumMovesItsOwnPatches() {
        var bass = ViolentSphere(subdivisions: 2)
        var treble = ViolentSphere(subdivisions: 2)
        let bassOnly = (0..<40).map { $0 < 4 ? Float(1) : 0 }
        let trebleOnly = (0..<40).map { $0 >= 36 ? Float(1) : 0 }
        run(&bass, seconds: 0.5, levels: bassOnly)
        run(&treble, seconds: 0.5, levels: trebleOnly)
        let mostBass = bass.radii.indices.max { bass.radii[$0] < bass.radii[$1] } ?? 0
        let mostTreble = treble.radii.indices.max { treble.radii[$0] < treble.radii[$1] } ?? 0
        #expect(simd_dot(bass.directions[mostBass], bass.directions[mostTreble]) < 0.9)
    }

    @Test func aDrumHitJoltsTheSpikesOutThenTheySettle() {
        var sphere = ViolentSphere(subdivisions: 2)
        let silence = [Float](repeating: 0, count: 40)
        run(&sphere, seconds: 0.5, levels: silence)
        let calm = average(sphere.radii)
        let spinBefore = sphere.spin
        sphere.update(levels: silence, beat: 1, elapsed: frame)
        #expect(average(sphere.radii) > calm + 0.1)
        run(&sphere, seconds: 1, levels: silence)
        #expect(abs(average(sphere.radii) - calm) < 0.05)
        // It spun on faster than a second's calm turn.
        #expect(sphere.spin - spinBefore > ViolentSphere.turn * 1.2)
    }

    @Test func aHeldBeatJoltsOnce() {
        var sphere = ViolentSphere(subdivisions: 1)
        let silence = [Float](repeating: 0, count: 40)
        sphere.update(levels: silence, beat: 1, elapsed: frame)
        let first = sphere.radii
        run(&sphere, seconds: 1, levels: silence, beat: 1)
        #expect(average(sphere.radii) < average(first))
    }
}
