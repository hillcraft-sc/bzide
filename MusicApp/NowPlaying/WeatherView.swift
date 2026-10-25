import NavidromeCore
import SwiftUI

/// The Storm visualizer (saved as `weather`, its earlier name): a small
/// landscape under a sky that follows the music (`WeatherSky` decides the
/// weather). Calm passages are clear with the
/// sun out; busy ones cloud over; the bass blows the wind, bending the trees;
/// treble rains in a storm; drum hits in a storm strike lightning, as a bolt,
/// never a flash of the whole screen. Fills the screen behind the controls.
struct WeatherView: View {
    let feed: SpectrumFeed
    let date: Date
    /// Four colors for the sky and hills: shades of the accent, or from the sweep.
    let colors: [Color]
    let insets: EdgeInsets
    let landscape: Bool
    let state: WeatherState

    var body: some View {
        let sky = state.update(feed: feed, at: date)
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
        Canvas { context, size in
            let layout = WeatherLayout(size: size, insets: insets, landscape: landscape)
            drawSky(sky, in: &context, layout: layout)
            drawSun(sky, in: &context, layout: layout)
            drawClouds(sky, in: &context, layout: layout)
            drawLightning(sky, in: &context, layout: layout)
            drawRain(sky, time: time, in: &context, layout: layout)
            drawLand(sky, time: time, in: &context, layout: layout)
        }
        // Darker under the menu at the top, and sideways toward the panel on the
        // right, so the white controls stay readable on a light sky.
        .overlay {
            LinearGradient(
                stops: [.init(color: .black.opacity(0.4), location: 0), .init(color: .clear, location: 0.2)],
                startPoint: .top, endPoint: .bottom
            )
            LinearGradient(
                stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.7), location: 1)],
                startPoint: .leading, endPoint: .trailing
            )
            .opacity(landscape ? 1 : 0)
        }
        .ignoresSafeArea()
    }

    private var palette: [Color] {
        colors.count >= 4 ? colors : Array(repeating: colors.first ?? .blue, count: 4)
    }

    // MARK: - Drawing

    /// Clear: the palette from dark overhead to light at the horizon. Overcast:
    /// storm grays. Lightning lifts it a little.
    private func drawSky(_ sky: WeatherSky, in context: inout GraphicsContext, layout: WeatherLayout) {
        let cover = sky.cloudCover * 0.7
        // Darkened a little, so light palettes still give white text a backdrop.
        let top = palette[0].mix(with: .black, by: 0.35).mix(with: Color(white: 0.08), by: cover)
        let low = palette[2].mix(with: .black, by: 0.12).mix(with: Color(white: 0.32), by: cover)
        let rect = CGRect(origin: .zero, size: layout.size)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [top, low]), startPoint: .zero, endPoint: CGPoint(x: 0, y: layout.horizon)
        ))
        if sky.flash > 0 {
            context.fill(Path(rect), with: .color(.white.opacity(sky.flash)))
        }
    }

    /// Fades out as the clouds come in.
    private func drawSun(_ sky: WeatherSky, in context: inout GraphicsContext, layout: WeatherLayout) {
        let opacity = 1 - min(sky.cloudCover * 1.3, 1)
        guard opacity > 0.01 else { return }
        let center = layout.sunCenter
        let radius = layout.sunRadius
        let warm = Color(red: 1, green: 0.88, blue: 0.62)
        let glow = Path(ellipseIn: CGRect(x: center.x - radius * 3, y: center.y - radius * 3, width: radius * 6, height: radius * 6))
        context.fill(glow, with: .radialGradient(
            Gradient(colors: [warm.opacity(0.45 * opacity), .clear]), center: center, startRadius: radius, endRadius: radius * 3
        ))
        let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(warm.opacity(opacity)))
    }

    /// Up to eight clouds drifting with the wind; more of them, and darker, as
    /// the sky clouds over. One light cloud stays even on clear days.
    private func drawClouds(_ sky: WeatherSky, in context: inout GraphicsContext, layout: WeatherLayout) {
        let color = Color(white: 0.97).mix(with: Color(white: 0.3), by: sky.cloudCover)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            for (index, cloud) in WeatherLayout.clouds.enumerated() {
                let opacity = min(max(sky.cloudCover * 10 - Double(index) + 1, 0), 1)
                guard opacity > 0 else { continue }
                let width = layout.size.width * cloud.size
                let span = layout.size.width + width * 2
                let travel = (cloud.start * span + sky.drift * cloud.speed * layout.size.width)
                    .truncatingRemainder(dividingBy: span)
                let origin = CGPoint(x: travel - width, y: layout.skyTop + (layout.horizon - layout.skyTop) * cloud.height)
                layer.fill(Self.cloudShape(at: origin, width: width), with: .color(color.opacity(0.92 * opacity)))
            }
        }
    }

    /// A cloud from overlapping puffs, `width` wide with its base at `origin.y`.
    static func cloudShape(at origin: CGPoint, width: CGFloat) -> Path {
        var path = Path()
        let puffs: [(x: CGFloat, size: CGFloat)] = [(0, 0.38), (0.2, 0.55), (0.45, 0.48), (0.66, 0.36)]
        for puff in puffs {
            let side = width * puff.size
            path.addEllipse(in: CGRect(x: origin.x + width * puff.x, y: origin.y - side * 0.75, width: side, height: side * 0.75))
        }
        path.addRoundedRect(
            in: CGRect(x: origin.x + width * 0.05, y: origin.y - width * 0.14, width: width * 0.92, height: width * 0.14),
            cornerSize: CGSize(width: width * 0.07, height: width * 0.07)
        )
        return path
    }

    private func drawLightning(_ sky: WeatherSky, in context: inout GraphicsContext, layout: WeatherLayout) {
        for bolt in sky.bolts {
            let fade = 1 - bolt.age / WeatherSky.boltLife
            let startY = layout.skyTop + (layout.horizon - layout.skyTop) * 0.2
            var path = Path()
            for points in bolt.paths {
                for (index, point) in points.enumerated() {
                    let location = CGPoint(
                        x: (bolt.x + point.x) * layout.size.width,
                        y: startY + point.y * (layout.horizon - startY)
                    )
                    index == 0 ? path.move(to: location) : path.addLine(to: location)
                }
            }
            context.stroke(path, with: .color(palette[2].mix(with: .white, by: 0.6).opacity(0.35 * fade)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.white.opacity(fade)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    /// Up to 160 streaks falling to the horizon, slanted by the wind.
    private func drawRain(_ sky: WeatherSky, time: TimeInterval, in context: inout GraphicsContext, layout: WeatherLayout) {
        let count = Int(sky.rain * 160)
        guard count > 0 else { return }
        let fall = layout.horizon
        let slant = CGFloat(sky.wind) * 10
        var streaks = Path()
        for drop in 0..<count {
            let seed = Double(drop)
            let x = (seed * 0.618_034).truncatingRemainder(dividingBy: 1) * (layout.size.width + 40) - 20
            let speed = 1.1 + (seed * 0.754_878).truncatingRemainder(dividingBy: 1) * 0.6
            let y = ((seed * 0.381_966 + time * speed).truncatingRemainder(dividingBy: 1)) * fall
            let start = CGPoint(x: x + slant * CGFloat(y / fall) * 4, y: y)
            streaks.move(to: start)
            streaks.addLine(to: CGPoint(x: start.x + slant, y: start.y + 16))
        }
        context.stroke(streaks, with: .color(.white.opacity(0.45)), lineWidth: 1.2)
    }

    /// Two rolling hills, the ground below them fading to black under the
    /// controls, and a row of trees bending with the wind.
    private func drawLand(_ sky: WeatherSky, time: TimeInterval, in context: inout GraphicsContext, layout: WeatherLayout) {
        let gloom = 0.3 + 0.4 * sky.cloudCover
        let far = palette[1].mix(with: .black, by: gloom)
        let near = palette[3].mix(with: .black, by: min(gloom + 0.2, 0.9))
        context.fill(layout.hill(height: 0.16, waves: (1.7, 0.4)), with: .color(far))
        context.fill(layout.hill(height: 0.08, waves: (2.6, 2.1)), with: .linearGradient(
            Gradient(colors: [near, .black]),
            startPoint: CGPoint(x: 0, y: layout.horizon - 40), endPoint: CGPoint(x: 0, y: layout.size.height)
        ))

        let trunk = near.mix(with: .black, by: 0.5)
        for (index, spot) in WeatherLayout.trees.enumerated() {
            let base = CGPoint(x: spot.x * layout.size.width, y: layout.groundY(atFraction: spot.x) + 2)
            let height = 34 * spot.size
            // Bent by the wind, swaying more the stronger it blows.
            let sway = sin(time * 2.4 + Double(index) * 1.3) * sky.wind * 0.3
            let lean = CGFloat(sky.wind * 0.6 + sway) * height * 0.5
            let top = CGPoint(x: base.x + lean, y: base.y - height)
            var stem = Path()
            stem.move(to: base)
            stem.addQuadCurve(to: top, control: CGPoint(x: base.x, y: base.y - height * 0.6))
            context.stroke(stem, with: .color(trunk), lineWidth: 3)
            let crown = height * 0.42
            context.fill(
                Path(ellipseIn: CGRect(x: top.x - crown, y: top.y - crown * 1.1, width: crown * 2, height: crown * 1.6)),
                with: .color(near.mix(with: palette[1], by: 0.25))
            )
        }
    }
}

/// Where the sky, sun, clouds and land sit.
struct WeatherLayout {
    let size: CGSize
    /// Below the menu at the top.
    let skyTop: CGFloat
    /// Where the hills meet the sky, above the title and controls in portrait.
    let horizon: CGFloat

    /// Sideways the sun moves left, out from behind the panel on the right.
    private let sunAcross: CGFloat

    init(size: CGSize, insets: EdgeInsets, landscape: Bool) {
        self.size = size
        sunAcross = landscape ? 0.42 : 0.72
        skyTop = insets.top
        horizon = landscape ? size.height * 0.8 : size.height - insets.bottom + 30
    }

    var sunRadius: CGFloat { min(size.width, size.height) * 0.07 }
    var sunCenter: CGPoint {
        CGPoint(x: size.width * sunAcross, y: skyTop + (horizon - skyTop) * 0.3)
    }

    /// Each cloud's place and look: where it starts across, how high (0 top of
    /// the sky ... 1 horizon), its width as a share of the screen, and its speed.
    static let clouds: [(start: Double, height: CGFloat, size: CGFloat, speed: Double)] = [
        (0.15, 0.4, 0.26, 1.0), (0.6, 0.12, 0.34, 1.3), (0.35, 0.4, 0.5, 0.8), (0.85, 0.3, 0.38, 1.15),
        (0.05, 0.08, 0.3, 1.4), (0.5, 0.5, 0.55, 0.7), (0.72, 0.18, 0.46, 0.9), (0.28, 0.32, 0.4, 1.05),
    ]

    /// Trees along the near hill: across the screen, and size.
    static let trees: [(x: Double, size: Double)] = [
        (0.08, 0.9), (0.14, 1.2), (0.31, 0.8), (0.55, 1.1), (0.61, 0.85), (0.86, 1.3), (0.93, 0.95),
    ]

    /// A hill rising up to `height` of the sky above the horizon, filled down to the bottom.
    func hill(height: CGFloat, waves: (Double, Double)) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for step in 0...60 {
            let fraction = Double(step) / 60
            path.addLine(to: CGPoint(x: fraction * size.width, y: hillY(atFraction: fraction, height: height, waves: waves)))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    /// The near hill's top at `fraction` across, for planting trees.
    func groundY(atFraction fraction: Double) -> CGFloat {
        hillY(atFraction: fraction, height: 0.08, waves: (2.6, 2.1))
    }

    private func hillY(atFraction fraction: Double, height: CGFloat, waves: (Double, Double)) -> CGFloat {
        let wave = (sin(fraction * .pi * waves.0 + waves.1) + 1) / 2 * 0.7 + (sin(fraction * .pi * waves.0 * 2.3) + 1) / 2 * 0.3
        return horizon - (horizon - skyTop) * height * CGFloat(wave)
    }
}

/// Keeps the weather between frames. A class so the drawing can advance it
/// each frame without changing view state mid-update.
@MainActor
final class WeatherState {
    private var sky = WeatherSky()
    private var lastFrame: Date?

    func update(feed: SpectrumFeed, at date: Date) -> WeatherSky {
        let elapsed = lastFrame.map { date.timeIntervalSince($0) } ?? 0
        lastFrame = date
        sky.update(energy: feed.energy, beat: feed.beat, elapsed: elapsed)
        return sky
    }
}
