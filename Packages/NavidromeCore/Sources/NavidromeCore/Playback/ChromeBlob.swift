import Foundation

/// The outline of the Chrome visualizer's liquid-metal blob: how far it
/// reaches at each angle around its middle, as a multiple of its resting
/// radius. Each spectrum band pushes out a bulge at its own angle, mirrored
/// left and right: bass at the bottom, treble at the top. Neighboring bulges
/// blend into one smooth shape, a slow wobble keeps it alive when quiet, and
/// a beat swells it all at once.
public enum ChromeBlob {
    /// Points around the outline; the shader blends between them.
    public static let pointCount = 128
    /// How far the loud bands push out (at most), and how much a beat swells everything.
    static let bulge = 0.4
    static let beatSwell = 0.08
    static let wobble = 0.025

    /// `pointCount` radii going clockwise from 3 o'clock (screen angles, y down).
    public static func radii(levels: [Float], beat: Float, time: TimeInterval) -> [Float] {
        let bands = levels.count
        return (0..<pointCount).map { point in
            let angle = Double(point) / Double(pointCount) * 2 * .pi
            // 0 at the bottom (6 o'clock), 1 at the top, the same on both sides.
            // Smooth through the top and bottom, so the outline has no crease there.
            let height = (1 - sin(angle)) / 2
            var push = 0.0
            if bands > 0 {
                // Each band's bulge spreads over its neighbors as a bell curve.
                let width = 1.6 / Double(bands)
                for band in 0..<bands {
                    let center = (Double(band) + 0.5) / Double(bands)
                    let distance = (height - center) / width
                    push += Double(min(max(levels[band], 0), 1)) * exp(-distance * distance)
                }
                // So every band at full level pushes about 1.
                push /= 1.6 * sqrt(Double.pi)
            }
            let alive = wobble * sin(angle * 3 + time * 0.9) + wobble * 0.6 * sin(angle * 5 - time * 1.3)
            return Float(1 + bulge * min(push, 1) + beatSwell * Double(beat) + alive)
        }
    }
}
