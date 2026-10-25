import NavidromeCore
import SwiftUI

/// The Spectrum visualizer, after an old-school LED equalizer: columns of
/// square segments rising and falling with the music, bass on the left, with
/// the unlit segments still faintly showing, and a gray dot over each column
/// that jumps with it and falls back with gravity (`SpectrumPeaks`).
struct SpectrumView: View {
    let levels: [Float]
    let date: Date
    /// The segments' colors from bottom to top, blended across the rows.
    let colors: [Color]
    let landscape: Bool
    let state: SpectrumState

    /// The classic meter: green at the bottom through yellow and orange to red.
    static let classic: [Color] = [
        Color(red: 0.2, green: 0.72, blue: 0.2),
        Color(red: 0.95, green: 0.82, blue: 0.15),
        Color(red: 1, green: 0.5, blue: 0.1),
        Color(red: 0.95, green: 0.2, blue: 0.15),
    ]
    static let peakColor = Color(white: 0.75)

    var body: some View {
        // Fewer, wider columns upright, so the segments keep their shape.
        let columns = SpectrumPeaks.columns(from: levels, count: landscape ? 40 : 20)
        let peaks = state.update(columns: columns, at: date)
        Canvas { context, size in
            let pitch = size.width / CGFloat(columns.count)
            // Segments a little wider than tall, as on the hardware.
            let rows = min(max(Int(size.height / (pitch * 0.6)), 12), 32)
            let rowPitch = size.height / CGFloat(rows)
            // One path per row for lit and unlit segments, and one for the
            // dots, so a frame is a few dozen fills rather than a thousand.
            var litRows = [Path](repeating: Path(), count: rows)
            var unlitRows = [Path](repeating: Path(), count: rows)
            var dots = Path()
            for (column, level) in columns.enumerated() {
                let lit = Int((CGFloat(level) * CGFloat(rows)).rounded())
                // Just above the top lit segment, or in the bottom row in silence.
                let peakRow = min(max(Int((CGFloat(peaks[column]) * CGFloat(rows)).rounded()), lit), rows - 1)
                for row in 0..<rows {
                    let cell = CGRect(
                        x: CGFloat(column) * pitch + pitch * 0.1,
                        y: size.height - CGFloat(row + 1) * rowPitch + rowPitch * 0.15,
                        width: pitch * 0.8,
                        height: rowPitch * 0.7
                    )
                    if row == peakRow {
                        dots.addRoundedRect(in: cell, cornerSize: Self.corner)
                    } else if row < lit {
                        litRows[row].addRoundedRect(in: cell, cornerSize: Self.corner)
                    } else {
                        unlitRows[row].addRoundedRect(in: cell, cornerSize: Self.corner)
                    }
                }
            }
            for row in 0..<rows {
                let color = color(at: Double(row) / Double(max(rows - 1, 1)))
                context.fill(litRows[row], with: .color(color))
                context.fill(unlitRows[row], with: .color(color.opacity(0.1)))
            }
            context.fill(dots, with: .color(Self.peakColor))
        }
    }

    private static let corner = CGSize(width: 1.5, height: 1.5)

    /// The color `position` (0 bottom, 1 top) of the way up, mixed between neighbors.
    private func color(at position: Double) -> Color {
        guard colors.count > 1 else { return colors.first ?? .white }
        let scaled = position * Double(colors.count - 1)
        let low = min(Int(scaled), colors.count - 1)
        let high = min(low + 1, colors.count - 1)
        return colors[low].mix(with: colors[high], by: scaled - Double(low))
    }
}

/// Keeps the peak dots between frames. A class so the drawing can advance
/// them each frame without changing view state mid-update.
@MainActor
final class SpectrumState {
    private var peaks = SpectrumPeaks(count: 0)
    private var lastFrame: Date?

    func update(columns: [Float], at date: Date) -> [Float] {
        let elapsed = lastFrame.map { date.timeIntervalSince($0) } ?? 0
        lastFrame = date
        peaks.update(columns: columns, elapsed: elapsed)
        return peaks.peaks
    }
}
