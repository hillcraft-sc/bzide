import Foundation

/// The droplets the Chrome blob splashes out on drum hits. Each flies out
/// from the edge, slows, and is pulled back like a bead of mercury until it
/// merges into the blob again, a few seconds later. Positions and sizes are
/// in multiples of the blob's resting radius, from its middle (y down).
public struct ChromeSplash: Sendable {
    public struct Droplet: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var size: Double
        var vx: Double
        var vy: Double
        var age: TimeInterval
    }

    public private(set) var droplets: [Droplet] = []

    /// The most at once; the shader draws a fixed number.
    public static let maxDroplets = 16
    /// A beat at least this strong splashes, at most this often.
    static let splashBeat: Float = 0.6
    static let splashGap: TimeInterval = 0.25
    /// How hard droplets are pulled back, and how much they're slowed.
    static let pull = 0.9
    static let drag = 1.0
    /// Where droplets start: past the edge of a blob at rest, so they leave
    /// even when it's bulging.
    static let startDistance = 1.3
    /// Inside this, a droplet that's on its way back has merged.
    static let mergeDistance = 1.05

    private var lastBeat: Float = 0
    private var sinceSplash: TimeInterval = .infinity
    private var splashCount: UInt64 = 0

    public init() {}

    /// Advances one frame. `room` is how far the free space reaches from the
    /// middle each way, in radii, so droplets stay in view.
    public mutating func update(beat: Float, elapsed: TimeInterval, room: (x: Double, y: Double)) {
        let step = min(max(elapsed, 0), 0.1)
        sinceSplash += step
        droplets = droplets.compactMap { move($0, step: step, room: room) }

        let isNewBeat = beat >= Self.splashBeat && lastBeat < Self.splashBeat
        lastBeat = beat
        if isNewBeat, sinceSplash >= Self.splashGap {
            sinceSplash = 0
            splash(strength: Double(beat))
        }
    }

    /// Three to five droplets from random places around the edge, harder hits
    /// throwing them further.
    private mutating func splash(strength: Double) {
        splashCount += 1
        let count = 3 + Int(Self.random(splashCount, 0) * 3)
        for index in 0..<count where droplets.count < Self.maxDroplets {
            let seed = UInt64(index) * 4 + 1
            let angle = Self.random(splashCount, seed) * 2 * .pi
            let speed = (2.4 + Self.random(splashCount, seed + 1) * 1.2) * (0.7 + 0.3 * strength)
            droplets.append(Droplet(
                x: cos(angle) * Self.startDistance, y: sin(angle) * Self.startDistance,
                size: 0.09 + Self.random(splashCount, seed + 2) * 0.11,
                vx: cos(angle) * speed, vy: sin(angle) * speed, age: 0
            ))
        }
    }

    /// One step of flying out and being pulled back; `nil` once it's merged.
    private func move(_ droplet: Droplet, step: TimeInterval, room: (x: Double, y: Double)) -> Droplet? {
        var droplet = droplet
        droplet.age += step
        droplet.vx += (-Self.pull * droplet.x - Self.drag * droplet.vx) * step
        droplet.vy += (-Self.pull * droplet.y - Self.drag * droplet.vy) * step
        droplet.x += droplet.vx * step
        droplet.y += droplet.vy * step
        // Kept inside the free space: it stops at the edge, then comes back.
        let limitX = max(room.x - droplet.size, 1)
        let limitY = max(room.y - droplet.size, 1)
        if abs(droplet.x) > limitX {
            droplet.x = droplet.x < 0 ? -limitX : limitX
            droplet.vx = 0
        }
        if abs(droplet.y) > limitY {
            droplet.y = droplet.y < 0 ? -limitY : limitY
            droplet.vy = 0
        }
        let distance = (droplet.x * droplet.x + droplet.y * droplet.y).squareRoot()
        let isReturning = droplet.x * droplet.vx + droplet.y * droplet.vy < 0
        return isReturning && distance < Self.mergeDistance ? nil : droplet
    }

    /// A repeatable number in 0..<1 for this seed and index (SplitMix64).
    static func random(_ seed: UInt64, _ index: UInt64) -> Double {
        var z = seed &* 0x9E37_79B9_7F4A_7C15 &+ index &* 0xBF58_476D_1CE4_E5B9 &+ 0x94D0_49BB_1331_11EB
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}
