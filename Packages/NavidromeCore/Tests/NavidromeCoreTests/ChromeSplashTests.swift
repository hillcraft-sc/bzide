import Foundation
import Testing
@testable import NavidromeCore

struct ChromeSplashTests {
    private let frame: TimeInterval = 1.0 / 60
    private let room = (x: 2.0, y: 2.5)

    private func run(_ splash: inout ChromeSplash, seconds: Double, beat: Float = 0) {
        for _ in 0..<Int(seconds * 60) {
            splash.update(beat: beat, elapsed: frame, room: room)
        }
    }

    @Test func noDrumsNoDroplets() {
        var splash = ChromeSplash()
        run(&splash, seconds: 5)
        #expect(splash.droplets.isEmpty)
    }

    @Test func aDrumHitSplashesAFewDropletsOutward() {
        var splash = ChromeSplash()
        // A beat held for a few frames is one splash.
        run(&splash, seconds: 0.05, beat: 1)
        #expect((3...5).contains(splash.droplets.count))
        let start = splash.droplets.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }
        run(&splash, seconds: 0.3)
        let later = splash.droplets.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }
        #expect(zip(start, later).allSatisfy { $1 > $0 })
    }

    @Test func dropletsComeBackAndMerge() {
        var splash = ChromeSplash()
        run(&splash, seconds: 0.05, beat: 1)
        run(&splash, seconds: 8)
        #expect(splash.droplets.isEmpty)
    }

    @Test func dropletsStayInTheFreeSpace() {
        var splash = ChromeSplash()
        for _ in 0..<20 {
            run(&splash, seconds: 0.05, beat: 1)
            run(&splash, seconds: 0.25)
            for droplet in splash.droplets {
                #expect(abs(droplet.x) + droplet.size <= room.x + 0.001)
                #expect(abs(droplet.y) + droplet.size <= room.y + 0.001)
            }
        }
    }

    @Test func fastDrumsAreCapped() {
        var splash = ChromeSplash()
        // A hit every 0.1 s for three seconds.
        for index in 0..<180 {
            splash.update(beat: index % 6 == 0 ? 1 : 0, elapsed: frame, room: room)
            #expect(splash.droplets.count <= ChromeSplash.maxDroplets)
        }
    }
}
