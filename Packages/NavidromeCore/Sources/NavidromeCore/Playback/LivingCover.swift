import Foundation

/// How one tile of the Living Cover visualizer moves this frame. Offsets are in
/// tile widths; with no music every tile is in place, so the cover is whole.
public struct CoverTileMotion: Sendable, Equatable {
    public var dx: Double
    public var dy: Double
    /// Radians.
    public var rotation: Double
    public var scale: Double
    /// 0...1: how brightly the tile's edges sparkle.
    public var sparkle: Double

    public static let still = CoverTileMotion(dx: 0, dy: 0, rotation: 0, scale: 1, sparkle: 0)
}

/// The Living Cover visualizer: the album cover cut into a grid of tiles that
/// move with the music. Bass and beats push the tiles out from the center; the
/// mids tilt them, neighbors in opposite directions; each tile also follows
/// its own band (bass in the middle, treble at the edges), lifting when it's
/// loud; treble makes the edges sparkle. Quiet passages put the cover back.
public enum LivingCover {
    public static let gridSize = 8

    public static func motion(
        row: Int, column: Int, gridSize: Int = gridSize,
        levels: [Float], energy: SpectrumEnergy, beat: Float
    ) -> CoverTileMotion {
        guard gridSize > 1 else { return .still }
        // The tile's center, from -1 (left/top edge) to 1 (right/bottom edge).
        let x = (Double(column) + 0.5) / Double(gridSize) * 2 - 1
        let y = (Double(row) + 0.5) / Double(gridSize) * 2 - 1
        let distance = min(hypot(x, y) / 2.0.squareRoot(), 1)

        // Its own band: bass at the middle, treble at the corners.
        let band = levels.isEmpty ? 0 : Double(levels[min(Int(distance * Double(levels.count - 1)), levels.count - 1)])
        let bass = Double(energy.bass), mid = Double(energy.mid), treble = Double(energy.treble)
        let push = bass * 0.55 + Double(beat) * 0.45
        let tilt = (row + column).isMultiple(of: 2) ? 1.0 : -1.0

        return CoverTileMotion(
            dx: x * push * 1.1,
            dy: y * push * 1.1,
            rotation: tilt * mid * 0.3,
            scale: 1 + band * 0.12 + Double(beat) * 0.05,
            sparkle: min(treble * 1.5 * (0.4 + band), 1)
        )
    }
}
