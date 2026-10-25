import Foundation
import simd

/// The Violent Sphere visualizer's shape: a ball of spikes, drawn as a fine
/// wireframe. The mesh is a geodesic sphere (an icosahedron, each triangle
/// split in four `subdivisions` times), so its points are spread evenly with
/// no crowding at the poles.
///
/// The music pushes the spikes out through **lobes**: patches of the sphere,
/// each playing one slice of the spectrum (the bass ones broad, the treble
/// ones narrow), scattered so neighbors play different parts. Each point
/// also has its own random length, which makes the jagged, hairy texture. A
/// strong drum hit **jolts** every spike outward and deals new lengths, and
/// spins the ball on; quiet, it settles to a calm, slightly rough ball.
///
/// Radii are multiples of the resting radius.
public struct ViolentSphere: Sendable {
    /// Each point's direction from the middle, unit length.
    public let directions: [SIMD3<Float>]
    /// Index triples, for the faces.
    public let triangles: [UInt32]
    /// Index pairs, each edge once, for the wireframe.
    public let edges: [UInt32]

    /// How far each point reaches now; `update` moves them.
    public private(set) var radii: [Float]
    /// How far the ball has turned, in radians.
    public private(set) var spin: Float = 0

    /// Each point's share of the lobes it's near (`shares[starts[point]..<starts[point + 1]]`);
    /// a point is in about three, so a frame is quick even unoptimized.
    private let shares: [(lobe: Int, weight: Float)]
    private let starts: [Int]
    /// Each lobe's slice of the spectrum, bass first: start and end, 0...1.
    private let lobeBands: [(start: Double, end: Double)]
    private var lengths: [Float]
    private var jolt: Float = 0
    private var lastBeat: Float = 0
    private var sinceJolt: TimeInterval = .infinity
    private var deals: UInt64 = 0

    static let lobeCount = 18
    /// How far the loudest lobe pushes its spikes, and the rough texture at rest.
    static let reach: Float = 0.8
    static let rest: Float = 0.06
    /// How far a jolt throws every spike, how fast it fades (per second), and
    /// what beat makes one, at most how often.
    static let joltReach: Float = 0.3
    static let joltFade: Float = 6
    static let joltBeat: Float = 0.6
    static let joltGap: TimeInterval = 0.25
    /// Nothing reaches past this, so the ball fits the space it's given.
    public static let maxRadius: Float = 1.85
    /// Radians a second when calm, and how much a jolt adds.
    static let turn: Float = 0.25
    static let joltTurn: Float = 2.5

    public init(subdivisions: Int = 5) {
        let mesh = Self.geodesic(subdivisions: subdivisions)
        directions = mesh.points
        triangles = mesh.triangles
        edges = Self.uniqueEdges(of: mesh.triangles)
        lobeBands = (0..<Self.lobeCount).map { lobe in
            (Double(lobe) / Double(Self.lobeCount), Double(lobe + 1) / Double(Self.lobeCount))
        }
        (shares, starts) = Self.lobeShares(for: mesh.points)
        lengths = Self.dealLengths(count: mesh.points.count, deal: 0)
        radii = [Float](repeating: 1, count: mesh.points.count)
    }

    /// Advances one frame lasting `elapsed` seconds.
    public mutating func update(levels: [Float], beat: Float, elapsed: TimeInterval) {
        let step = min(max(elapsed, 0), 0.1)
        sinceJolt += step
        if beat >= Self.joltBeat, lastBeat < Self.joltBeat, sinceJolt >= Self.joltGap {
            sinceJolt = 0
            jolt = 1
            deals += 1
            lengths = Self.dealLengths(count: directions.count, deal: deals)
        }
        lastBeat = beat
        spin += (Self.turn + Self.joltTurn * jolt) * Float(step)
        spin = spin.truncatingRemainder(dividingBy: 2 * .pi)

        let strengths = lobeBands.map { Self.level(of: levels, from: $0.start, to: $0.end) }
        for point in radii.indices {
            var push: Float = 0
            for share in shares[starts[point]..<starts[point + 1]] {
                push += share.weight * strengths[share.lobe]
            }
            let length = lengths[point]
            let radius = 1 + Self.rest * length + Self.reach * min(push, 1.2) * length + Self.joltReach * jolt * length
            radii[point] = min(radius, Self.maxRadius)
        }
        jolt *= exp(-Self.joltFade * Float(step))
        if jolt < 0.001 { jolt = 0 }
    }

    /// The average of `levels` from `start` to `end` of the way along (0...1).
    private static func level(of levels: [Float], from start: Double, to end: Double) -> Float {
        guard !levels.isEmpty else { return 0 }
        let low = min(Int(start * Double(levels.count)), levels.count - 1)
        let high = max(min(Int((end * Double(levels.count)).rounded(.up)), levels.count), low + 1)
        let slice = levels[low..<high]
        return min(max(slice.reduce(0, +) / Float(slice.count), 0), 1)
    }

    /// A new length for each point, mostly long with some short, so the
    /// spikes are ragged. The same deal gives the same lengths.
    private static func dealLengths(count: Int, deal: UInt64) -> [Float] {
        (0..<count).map { point in
            let random = ChromeSplash.random(deal &+ 0x5F3A, UInt64(point))
            return Float(0.25 + 0.75 * random.squareRoot())
        }
    }

    // MARK: - Lobes

    /// Each point's share of each lobe: a falloff around the lobe's middle,
    /// broad for the bass lobes and narrow for the treble. Shares too small
    /// to see are left out.
    private static func lobeShares(for points: [SIMD3<Float>]) -> ([(lobe: Int, weight: Float)], [Int]) {
        let middles = lobeMiddles()
        var shares: [(lobe: Int, weight: Float)] = []
        var starts = [0]
        for point in points {
            for lobe in 0..<lobeCount {
                let position = Float(lobe) / Float(lobeCount - 1)
                // In 1 - cos(angle): about 40° across for bass, 20° for treble.
                let width: Float = 0.12 - 0.09 * position
                let weight = exp(-(1 - simd_dot(point, middles[lobe])) / width)
                if weight > 0.01 { shares.append((lobe, weight)) }
            }
            starts.append(shares.count)
        }
        return (shares, starts)
    }

    /// The lobes' middles, spread evenly over the sphere (a Fibonacci
    /// spiral), then dealt out of order so neighbors play different bands.
    private static func lobeMiddles() -> [SIMD3<Float>] {
        let golden = Float.pi * (3 - Float(5).squareRoot())
        let spread = (0..<lobeCount).map { index -> SIMD3<Float> in
            let y = 1 - 2 * (Float(index) + 0.5) / Float(lobeCount)
            let ring = (1 - y * y).squareRoot()
            let angle = golden * Float(index)
            return SIMD3(ring * cos(angle), y, ring * sin(angle))
        }
        // Stepping by 7 (coprime with 18) visits every spot once, far apart.
        return (0..<lobeCount).map { spread[($0 * 7) % lobeCount] }
    }

    // MARK: - Mesh

    static func geodesic(subdivisions: Int) -> (points: [SIMD3<Float>], triangles: [UInt32]) {
        let t = (1 + Float(5).squareRoot()) / 2
        let corners: [SIMD3<Float>] = [
            SIMD3(-1, t, 0), SIMD3(1, t, 0), SIMD3(-1, -t, 0), SIMD3(1, -t, 0),
            SIMD3(0, -1, t), SIMD3(0, 1, t), SIMD3(0, -1, -t), SIMD3(0, 1, -t),
            SIMD3(t, 0, -1), SIMD3(t, 0, 1), SIMD3(-t, 0, -1), SIMD3(-t, 0, 1),
        ]
        var points = corners.map { simd_normalize($0) }
        var triangles: [UInt32] = [
            0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
            1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
            3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
            4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
        ]
        for _ in 0..<max(subdivisions, 0) {
            var middles: [UInt64: UInt32] = [:]
            func middle(_ a: UInt32, _ b: UInt32) -> UInt32 {
                let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                if let known = middles[key] { return known }
                points.append(simd_normalize(points[Int(a)] + points[Int(b)]))
                let index = UInt32(points.count - 1)
                middles[key] = index
                return index
            }
            var split: [UInt32] = []
            split.reserveCapacity(triangles.count * 4)
            for corner in stride(from: 0, to: triangles.count, by: 3) {
                let (a, b, c) = (triangles[corner], triangles[corner + 1], triangles[corner + 2])
                let (ab, bc, ca) = (middle(a, b), middle(b, c), middle(c, a))
                split += [a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]
            }
            triangles = split
        }
        return (points, triangles)
    }

    static func uniqueEdges(of triangles: [UInt32]) -> [UInt32] {
        var seen = Set<UInt64>()
        var edges: [UInt32] = []
        for corner in stride(from: 0, to: triangles.count, by: 3) {
            let corners = [triangles[corner], triangles[corner + 1], triangles[corner + 2]]
            for (a, b) in [(corners[0], corners[1]), (corners[1], corners[2]), (corners[2], corners[0])] {
                if seen.insert(UInt64(min(a, b)) << 32 | UInt64(max(a, b))).inserted {
                    edges += [a, b]
                }
            }
        }
        return edges
    }
}
