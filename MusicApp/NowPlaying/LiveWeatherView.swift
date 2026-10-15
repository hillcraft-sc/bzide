import NavidromeCore
import SwiftUI

/// The Weather (Live) visualizer: the real time of day, in natural colors,
/// over Weather's landscape, with the music moving within it (`LiveSky`).
/// Every beat flares the stars and swells the sun's and moon's glow. Night has
/// stars twinkling with the treble, the moon in its real phase, shooting stars
/// and comets on the beats, and fireflies over the hills; day has the sun with
/// rays pulsing with the bass and birds crossing when the music builds or is
/// energetic; dawn and dusk glow in between. Fills the screen behind the
/// controls.
struct LiveWeatherView: View {
    let feed: SpectrumFeed
    let date: Date
    let insets: EdgeInsets
    let landscape: Bool
    let state: LiveWeatherState
    /// Debug builds only: a forced weather and time of day, for trying each.
    var forced: LiveWeatherDebug = .init()

    var body: some View {
        let frame = state.update(feed: feed, at: date, forced: forced)
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
        Canvas { context, size in
            let layout = WeatherLayout(size: size, insets: insets, landscape: landscape)
            let light = SkyLight(sunAltitude: frame.sun.altitude, cloudCover: frame.sky.cloudCover, gloom: Self.gloom(frame.sky))
            drawSky(light, in: &context, layout: layout)
            drawStars(frame, light: light, time: time, in: &context, layout: layout)
            drawMoon(frame, light: light, in: &context, layout: layout)
            drawShootingStars(frame.sky, light: light, in: &context, layout: layout)
            drawSun(frame, light: light, time: time, in: &context, layout: layout)
            drawClouds(frame.sky, light: light, in: &context, layout: layout)
            drawLightning(frame.sky, in: &context, layout: layout)
            drawBirds(frame.sky, light: light, time: time, in: &context, layout: layout)
            drawPrecipitation(frame.sky, light: light, time: time, in: &context, layout: layout)
            drawLand(frame.sky, light: light, time: time, in: &context, layout: layout)
            drawFog(frame.sky, light: light, time: time, in: &context, layout: layout)
            if frame.sky.weather.precipitation == .none {
                drawFireflies(frame.sky, light: light, time: time, in: &context, layout: layout)
            }
        }
        // As Weather: darker under the menu, and toward the side panel.
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

    // MARK: - Sky

    /// 0 ... 1: how dark and heavy the weather makes the clouds and sky:
    /// darker the harder it rains or snows, darkest in a thunderstorm.
    static func gloom(_ sky: LiveSky) -> Double {
        let falling = sky.weather.precipitation == .none ? 0 : 0.3 + 0.4 * sky.precipitation
        return min(max(falling, sky.weather.isThunder ? 0.75 : 0, sky.fog * 0.4), 1)
    }

    private func drawSky(_ light: SkyLight, in context: inout GraphicsContext, layout: WeatherLayout) {
        let rect = CGRect(origin: .zero, size: layout.size)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [light.skyTop, light.skyHorizon]), startPoint: .zero, endPoint: CGPoint(x: 0, y: layout.horizon)
        ))
    }

    /// Weather's bolts, and a slight lift of the sky while one is bright.
    private func drawLightning(_ sky: LiveSky, in context: inout GraphicsContext, layout: WeatherLayout) {
        for bolt in sky.bolts {
            let fade = 1 - bolt.age / WeatherSky.boltLife
            let startY = layout.skyTop + (layout.horizon - layout.skyTop) * 0.2
            var path = Path()
            for points in bolt.paths {
                for (index, point) in points.enumerated() {
                    let location = CGPoint(x: (bolt.x + point.x) * layout.size.width, y: startY + point.y * (layout.horizon - startY))
                    index == 0 ? path.move(to: location) : path.addLine(to: location)
                }
            }
            context.fill(Path(CGRect(origin: .zero, size: layout.size)), with: .color(.white.opacity(0.08 * fade)))
            context.stroke(path, with: .color(Color(red: 0.75, green: 0.8, blue: 1).opacity(0.35 * fade)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.white.opacity(fade)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - Rain, sleet, snow and fog

    /// Rain as streaks slanted by the wind; snow as flakes swaying down and
    /// swirling in the gusts; sleet as both. Up to 260 at a time.
    private func drawPrecipitation(_ sky: LiveSky, light: SkyLight, time: TimeInterval, in context: inout GraphicsContext, layout: WeatherLayout) {
        let kind = sky.weather.precipitation
        let count = Int(sky.precipitation * 260)
        guard kind != .none, count > 0 else { return }
        let fall = layout.horizon + 20
        let wind = CGFloat(sky.wind)
        // Lit by the sky: bright by day, dim at night.
        let tone = Color.white.opacity(0.25 + 0.3 * light.daylight)
        var streaks = Path()
        var flakes = Path()
        for drop in 0..<count {
            let seed = Double(drop)
            let across = (seed * 0.618_034).truncatingRemainder(dividingBy: 1)
            let isFlake = kind == .snow || (kind == .sleet && drop % 2 == 0)
            if isFlake {
                let speed = 0.12 + (seed * 0.754_878).truncatingRemainder(dividingBy: 1) * 0.1
                let y = ((seed * 0.381_966 + time * speed * (1 + Double(wind))).truncatingRemainder(dividingBy: 1)) * fall
                let sway = CGFloat(sin(time * 1.3 + seed)) * 10 + wind * 60 * CGFloat(y / fall)
                let x = (across * (layout.size.width + 80) - 40) + sway
                let size: CGFloat = 1.5 + CGFloat((seed * 0.29).truncatingRemainder(dividingBy: 1)) * 2.5
                flakes.addEllipse(in: CGRect(x: x, y: y, width: size, height: size))
            } else {
                let speed = 1.0 + (seed * 0.754_878).truncatingRemainder(dividingBy: 1) * 0.6
                let y = ((seed * 0.381_966 + time * speed).truncatingRemainder(dividingBy: 1)) * fall
                let slant = wind * 14
                let x = across * (layout.size.width + 60) - 30 + slant * CGFloat(y / fall) * 4
                streaks.move(to: CGPoint(x: x, y: y))
                streaks.addLine(to: CGPoint(x: x + slant, y: y + 16 + 8 * sky.precipitation))
            }
        }
        context.stroke(streaks, with: .color(tone), lineWidth: 1.1)
        context.fill(flakes, with: .color(.white.opacity(0.55 + 0.35 * light.daylight)))
    }

    /// Soft bands drifting across the hills, thicker in calm passages.
    private func drawFog(_ sky: LiveSky, light: SkyLight, time: TimeInterval, in context: inout GraphicsContext, layout: WeatherLayout) {
        guard sky.fog > 0.02 else { return }
        let color = light.skyHorizon.mix(with: Color(white: 0.85), by: 0.5)
        // A haze over everything, thickest at the horizon.
        context.fill(Path(CGRect(origin: .zero, size: layout.size)), with: .linearGradient(
            Gradient(stops: [
                .init(color: color.opacity(0.35 * sky.fog), location: 0),
                .init(color: color.opacity(0.8 * sky.fog), location: 0.85),
                .init(color: color.opacity(0.5 * sky.fog), location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: layout.skyTop), endPoint: CGPoint(x: 0, y: layout.size.height)
        ))
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            for band in 0..<5 {
                let height = layout.horizon - (layout.horizon - layout.skyTop) * (0.05 + 0.13 * CGFloat(band))
                let shift = CGFloat((sky.drift * (0.4 + 0.15 * Double(band)) + Double(band) * 0.37).truncatingRemainder(dividingBy: 1))
                for copy in 0..<2 {
                    let x = (shift + CGFloat(copy) - 1) * layout.size.width * 1.2
                    let rect = CGRect(x: x, y: height - 40, width: layout.size.width * 1.3, height: 80)
                    layer.fill(Path(ellipseIn: rect), with: .color(color.opacity(min(sky.fog * (0.9 - 0.1 * Double(band)), 1))))
                }
            }
        }
    }

    /// A fixed field of stars, fading in as the sky darkens. Each twinkles at
    /// its own pace, harder when the treble is bright.
    private func drawStars(_ frame: LiveWeatherState.Frame, light: SkyLight, time: TimeInterval, in context: inout GraphicsContext, layout: WeatherLayout) {
        let visibility = light.starVisibility
        guard visibility > 0.01 else { return }
        let skyHeight = layout.horizon - layout.skyTop
        for index in 0..<Self.starCount {
            let seed = UInt64(index)
            let x = Double(LightningBolt.random(seed, 11)) * layout.size.width
            // More stars high up, fewer near the hazy horizon.
            let height = pow(Double(LightningBolt.random(seed, 12)), 1.6)
            let y = layout.skyTop + skyHeight * height * 0.9
            let size = 0.8 + 1.8 * Double(LightningBolt.random(seed, 13))
            let speed = 1.5 + 3 * Double(LightningBolt.random(seed, 14))
            let twinkle = 0.5 + 0.5 * sin(time * speed * (1 + frame.sky.sparkle * 2) + Double(index))
            // Each beat flares them all, the bigger ones most.
            let flare = frame.sky.flash * (0.3 + 0.7 * Double(LightningBolt.random(seed, 15)))
            let opacity = min(visibility * (0.35 + 0.65 * twinkle * (0.5 + frame.sky.sparkle * 0.5) + flare * 0.6) * (1 - height * 0.4), 1)
            let rect = CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
            // The brightest few get a soft cross of light when they flare.
            if size > 2.2, twinkle > 0.85 || flare > 0.6 {
                let flare = size * 3 * max(twinkle, flare)
                var cross = Path()
                cross.move(to: CGPoint(x: x - flare, y: y))
                cross.addLine(to: CGPoint(x: x + flare, y: y))
                cross.move(to: CGPoint(x: x, y: y - flare))
                cross.addLine(to: CGPoint(x: x, y: y + flare))
                context.stroke(cross, with: .color(.white.opacity(opacity * 0.5)), lineWidth: 0.6)
            }
        }
    }

    static let starCount = 140

    /// The moon in its real phase, high on the side away from the panel, at
    /// night and in deep twilight.
    private func drawMoon(_ frame: LiveWeatherState.Frame, light: SkyLight, in context: inout GraphicsContext, layout: WeatherLayout) {
        let visibility = light.starVisibility
        let lit = frame.moonIllumination
        guard visibility > 0.05, lit > 0.03 else { return }
        let radius = layout.sunRadius * 0.8
        let center = CGPoint(x: layout.size.width * (landscape ? 0.18 : 0.24), y: layout.skyTop + (layout.horizon - layout.skyTop) * 0.22)
        let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let moonlight = Color(red: 0.96, green: 0.95, blue: 0.86)
        // A soft glow, stronger the fuller it is.
        context.fill(
            Path(ellipseIn: disc.insetBy(dx: -radius * 2, dy: -radius * 2)),
            with: .radialGradient(
                Gradient(colors: [moonlight.opacity((0.25 + 0.25 * frame.sky.flash) * lit * visibility), .clear]),
                center: center, startRadius: radius, endRadius: radius * (3 + frame.sky.flash)
            )
        )
        // The dark part faintly visible, then the lit part: half the disc on
        // the lit side, plus or minus an ellipse for the terminator.
        context.fill(Path(ellipseIn: disc), with: .color(Color(white: 0.2).opacity(0.5 * visibility)))
        // Waxing, the right side is lit (as seen from the north); waning, the left.
        let waxing = frame.moonPhase < 0.5
        var half = Path()
        half.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: !waxing)
        half.closeSubpath()
        // The terminator is an ellipse as wide as the lit part is past (or
        // short of) half: added for a gibbous moon, cut out for a crescent.
        let width = abs(CGFloat(cos(2 * .pi * frame.moonPhase))) * radius
        let terminator = Path(ellipseIn: CGRect(x: center.x - width, y: center.y - radius, width: width * 2, height: radius * 2))
        let lightPath = lit > 0.5 ? half.union(terminator) : half.subtracting(terminator)
        context.fill(lightPath, with: .color(moonlight.opacity(visibility)))
    }

    /// A streak with a bright head; a comet is slower, with a long, soft tail.
    private func drawShootingStars(_ sky: LiveSky, light: SkyLight, in context: inout GraphicsContext, layout: WeatherLayout) {
        guard light.starVisibility > 0.05 else { return }
        let skyHeight = layout.horizon - layout.skyTop
        for star in sky.shootingStars {
            let start = CGPoint(x: star.start.x * layout.size.width, y: layout.skyTop + star.start.y * skyHeight)
            let travel = (star.isComet ? 0.35 : 0.55) * Double(min(layout.size.width, skyHeight))
            let direction = CGPoint(x: cos(star.angle), y: sin(star.angle) * 0.6)
            let distance = travel * (star.isComet ? star.progress : sqrt(star.progress))
            let head = CGPoint(x: start.x + direction.x * distance, y: start.y + direction.y * distance)
            let tailLength = star.isComet ? travel * 0.45 : min(distance, travel * 0.3)
            let tail = CGPoint(x: head.x - direction.x * tailLength, y: head.y - direction.y * tailLength)
            // In quickly, out slowly.
            let fade = min(star.progress * 6, 1) * (1 - pow(star.progress, star.isComet ? 3 : 2))
            let opacity = fade * light.starVisibility
            var streak = Path()
            streak.move(to: tail)
            streak.addLine(to: head)
            let gradient = Gradient(colors: [.clear, Color.white.opacity(opacity)])
            if star.isComet {
                let blue = Color(red: 0.7, green: 0.85, blue: 1)
                context.stroke(streak, with: .linearGradient(Gradient(colors: [.clear, blue.opacity(opacity * 0.5)]), startPoint: tail, endPoint: head), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                context.stroke(streak, with: .linearGradient(gradient, startPoint: tail, endPoint: head), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                let glow = CGRect(x: head.x - 8, y: head.y - 8, width: 16, height: 16)
                context.fill(Path(ellipseIn: glow), with: .radialGradient(Gradient(colors: [.white.opacity(opacity), .clear]), center: head, startRadius: 0, endRadius: 8))
            } else {
                context.stroke(streak, with: .linearGradient(gradient, startPoint: tail, endPoint: head), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }

    // MARK: - Sun

    /// Rises on the left and sets on the right, following its real height,
    /// with rays that pulse with the bass when the sky is clear.
    private func drawSun(_ frame: LiveWeatherState.Frame, light: SkyLight, time: TimeInterval, in context: inout GraphicsContext, layout: WeatherLayout) {
        let altitude = frame.sun.altitude
        guard altitude > -3 else { return }
        let center = sunCenter(frame.sun, layout: layout)
        let radius = layout.sunRadius
        let clear = 1 - min(frame.sky.cloudCover * 1.2, 1)
        let color = light.sunColor
        // Glow: wide and warm near the horizon.
        let glowRadius = radius * (3 + 2 * light.goldenness + 1.2 * frame.sky.flash)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
            with: .radialGradient(Gradient(colors: [color.opacity((0.5 + 0.3 * frame.sky.flash) * clear), .clear]), center: center, startRadius: radius, endRadius: glowRadius)
        )
        // Rays, by day, longer on the bass.
        if light.daylight > 0.3, clear > 0.2 {
            let rays = 12
            let length = radius * (0.6 + 1.4 * frame.sky.pulse)
            var path = Path()
            for ray in 0..<rays {
                // Turned by the wind's travel, so they spin faster in energetic music.
                let angle = Double(ray) / Double(rays) * 2 * .pi + frame.sky.drift * 0.6
                let inner = CGPoint(x: center.x + cos(angle) * radius * 1.3, y: center.y + sin(angle) * radius * 1.3)
                let outer = CGPoint(x: center.x + cos(angle) * (radius * 1.3 + length), y: center.y + sin(angle) * (radius * 1.3 + length))
                path.move(to: inner)
                path.addLine(to: outer)
            }
            context.stroke(path, with: .color(color.opacity(0.35 * clear * light.daylight)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        // Behind thick cloud it's gone, not a gray disc.
        guard clear > 0.02 else { return }
        let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(color.opacity(min(clear * 1.5, 1))))
    }

    private func sunCenter(_ sun: SkyClock.Sun, layout: WeatherLayout) -> CGPoint {
        // Across: −100° (morning) on the left to +100° (evening) on the right,
        // kept clear of the side panel sideways.
        let across = (min(max(sun.hourAngle, -100), 100) + 100) / 200
        let span = landscape ? 0.65 : 0.8
        let x = layout.size.width * (0.1 + span * across)
        // Up: the horizon at 0°, near the top of the sky by 50°.
        let up = min(max(sun.altitude + 3, 0) / 53, 1)
        let y = layout.horizon - (layout.horizon - layout.skyTop) * (0.05 + 0.75 * up)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Clouds and birds

    private func drawClouds(_ sky: LiveSky, light: SkyLight, in context: inout GraphicsContext, layout: WeatherLayout) {
        // Past half cover, a deck of cloud closes over the sky from the top,
        // down to the horizon when overcast.
        let deck = min(max((sky.cloudCover - 0.5) * 2, 0), 1)
        if deck > 0 {
            let bottom = layout.skyTop + (layout.horizon - layout.skyTop) * (0.35 + 0.65 * deck)
            context.fill(Path(CGRect(x: 0, y: 0, width: layout.size.width, height: bottom)), with: .linearGradient(
                Gradient(stops: [
                    .init(color: light.cloudColor.opacity(0.95 * deck), location: 0),
                    .init(color: light.cloudColor.opacity(0.8 * deck), location: 0.6),
                    .init(color: light.cloudColor.opacity(0), location: 1),
                ]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: bottom)
            ))
        }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            for (index, cloud) in WeatherLayout.clouds.enumerated() {
                let opacity = min(max(sky.cloudCover * 10 - Double(index) + 1, 0), 1)
                guard opacity > 0 else { continue }
                let width = layout.size.width * cloud.size
                let span = layout.size.width + width * 2
                let travel = (cloud.start * span + sky.drift * cloud.speed * layout.size.width).truncatingRemainder(dividingBy: span)
                let origin = CGPoint(x: travel - width, y: layout.skyTop + (layout.horizon - layout.skyTop) * cloud.height)
                layer.fill(WeatherView.cloudShape(at: origin, width: width), with: .color(light.cloudColor.opacity(0.85 * opacity)))
            }
        }
    }

    /// Each flock in a loose V, wings flapping, crossing the sky.
    private func drawBirds(_ sky: LiveSky, light: SkyLight, time: TimeInterval, in context: inout GraphicsContext, layout: WeatherLayout) {
        let color = light.birdColor
        for flock in sky.flocks {
            let skyHeight = layout.horizon - layout.skyTop
            let travel = flock.progress * (layout.size.width + 200) - 100
            let leadX = flock.isHeadingRight ? travel : layout.size.width - travel
            let leadY = layout.skyTop + skyHeight * flock.height + CGFloat(sin(flock.age * 0.8)) * 10
            let back: CGFloat = flock.isHeadingRight ? -1 : 1
            var path = Path()
            for bird in 0..<flock.size {
                // Alternate sides of the V, each a little further back.
                let rank = CGFloat((bird + 1) / 2)
                let side: CGFloat = bird % 2 == 0 ? 1 : -1
                let x = leadX + back * rank * 16
                let y = leadY + (bird == 0 ? 0 : side * rank * 9)
                let flap = CGFloat(sin(time * 9 + Double(bird) * 0.9))
                let span: CGFloat = 6
                path.move(to: CGPoint(x: x - span, y: y - 3 * flap))
                path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - span / 2, y: y - 4 * flap - 2))
                path.addQuadCurve(to: CGPoint(x: x + span, y: y - 3 * flap), control: CGPoint(x: x + span / 2, y: y - 4 * flap - 2))
            }
            // Fade in and out at the edges of the crossing.
            let fade = min(flock.progress * 8, 1) * min((1 - flock.progress) * 8, 1)
            context.stroke(path, with: .color(color.opacity(fade)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - Fireflies

    /// At dusk and night, glowing dots drifting over the hills: more of them
    /// the more energetic the music, brighter with the mid-range, all flaring
    /// on the beat.
    private func drawFireflies(_ sky: LiveSky, light: SkyLight, time: TimeInterval, in context: inout GraphicsContext, layout: WeatherLayout) {
        let visibility = min(max((0.6 - light.daylight) / 0.4, 0), 1)
        guard visibility > 0.01 else { return }
        let count = Int(3 + 7 * sky.intensity)
        let band = (layout.horizon - layout.skyTop) * 0.22
        let color = Color(red: 0.86, green: 1, blue: 0.48)
        for index in 0..<count {
            let seed = UInt64(1000 + index)
            let speed = 0.15 + 0.25 * Double(LightningBolt.random(seed, 1))
            let x = (Double(LightningBolt.random(seed, 2)) + sin(time * speed + Double(index)) * 0.06)
                .truncatingRemainder(dividingBy: 1) * layout.size.width
            let y = layout.horizon - band * (0.1 + 0.9 * Double(LightningBolt.random(seed, 3))) + CGFloat(sin(time * speed * 1.7 + Double(index) * 2)) * 12
            let blink = 0.5 + 0.5 * sin(time * (1.2 + 2 * Double(LightningBolt.random(seed, 4))) + Double(index))
            let brightness = min((0.2 + 0.6 * sky.glow) * blink + sky.flash * 0.4, 0.85) * visibility
            guard brightness > 0.02 else { continue }
            let radius = 2 + 5 * brightness
            let center = CGPoint(x: x, y: y)
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius * 2, y: y - radius * 2, width: radius * 4, height: radius * 4)),
                with: .radialGradient(Gradient(colors: [color.opacity(0.6 * brightness), .clear]), center: center, startRadius: 0, endRadius: radius * 2)
            )
            context.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(color.opacity(brightness)))
        }
    }

    // MARK: - Land

    private func drawLand(_ sky: LiveSky, light: SkyLight, time: TimeInterval, in context: inout GraphicsContext, layout: WeatherLayout) {
        context.fill(layout.hill(height: 0.16, waves: (1.7, 0.4)), with: .color(light.farHill))
        context.fill(layout.hill(height: 0.08, waves: (2.6, 2.1)), with: .linearGradient(
            Gradient(colors: [light.nearHill, .black]),
            startPoint: CGPoint(x: 0, y: layout.horizon - 40), endPoint: CGPoint(x: 0, y: layout.size.height)
        ))
        let trunk = light.nearHill.mix(with: .black, by: 0.5)
        let crown = light.nearHill.mix(with: light.farHill, by: 0.3)
        for (index, spot) in WeatherLayout.trees.enumerated() {
            let base = CGPoint(x: spot.x * layout.size.width, y: layout.groundY(atFraction: spot.x) + 2)
            let height = 34 * spot.size
            let sway = sin(time * 2.4 + Double(index) * 1.3) * sky.wind * 0.3
            let lean = CGFloat(sky.wind * 0.6 + sway) * height * 0.5
            let top = CGPoint(x: base.x + lean, y: base.y - height)
            var stem = Path()
            stem.move(to: base)
            stem.addQuadCurve(to: top, control: CGPoint(x: base.x, y: base.y - height * 0.6))
            context.stroke(stem, with: .color(trunk), lineWidth: 3)
            let size = height * 0.42
            context.fill(
                Path(ellipseIn: CGRect(x: top.x - size, y: top.y - size * 1.1, width: size * 2, height: size * 1.6)),
                with: .color(crown)
            )
        }
    }
}

/// The scene's colors for the sun's height: night, twilight, golden hour and
/// day blend smoothly, and clouds gray them. Natural colors, not the theme's.
struct SkyLight {
    let skyTop: Color
    let skyHorizon: Color
    let sunColor: Color
    let cloudColor: Color
    let birdColor: Color
    let farHill: Color
    let nearHill: Color
    /// 0 (night) ... 1 (full day).
    let daylight: Double
    /// 0 ... 1: how strongly the low sun colors things.
    let goldenness: Double
    /// 0 ... 1: how visible the stars and moon are.
    let starVisibility: Double

    init(sunAltitude altitude: Double, cloudCover: Double, gloom: Double = 0) {
        let keys = Self.keys
        // Between which two keyframes the sun is, and how far.
        let upper = keys.firstIndex { $0.altitude >= altitude } ?? keys.count - 1
        let lower = max(upper - 1, 0)
        let span = keys[upper].altitude - keys[lower].altitude
        let fraction = span > 0 ? min(max((altitude - keys[lower].altitude) / span, 0), 1) : 0
        func blend(_ part: KeyPath<Key, Color>) -> Color {
            keys[lower][keyPath: part].mix(with: keys[upper][keyPath: part], by: fraction)
        }
        let gray = Color(white: 0.45)
        let overcast = min(cloudCover * 0.6 + gloom * 0.3, 0.9)
        skyTop = blend(\.top).mix(with: gray.mix(with: .black, by: 0.4), by: overcast)
        skyHorizon = blend(\.horizon).mix(with: gray, by: overcast)
        sunColor = blend(\.sun)
        // Dull and darker under heavy cloud and weather.
        let dull = min(cloudCover * 0.25 + gloom * 0.35, 0.55)
        farHill = blend(\.farHill).mix(with: Color(white: 0.25), by: dull)
        nearHill = blend(\.nearHill).mix(with: Color(white: 0.12), by: dull)
        daylight = LiveSky.darkness(sunAltitude: altitude).complement
        // Strongest with the sun just above the horizon.
        goldenness = max(0, 1 - abs(altitude - 2) / 10)
        // Hidden by cloud: half cover dims them, overcast hides them.
        starVisibility = min(max((-altitude - 4) / 10, 0), 1) * min(max(1.6 - cloudCover * 1.8, 0), 1)
        cloudColor = Color.white.mix(with: blend(\.horizon), by: 0.35 + 0.4 * goldenness)
            .mix(with: Color(white: 0.15), by: (1 - daylight) * 0.7)
            .mix(with: Color(white: 0.22), by: gloom * 0.75)
        birdColor = Color(white: 0.12).mix(with: .black, by: 0.5)
    }

    struct Key {
        let altitude: Double
        let top: Color
        let horizon: Color
        let sun: Color
        let farHill: Color
        let nearHill: Color
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Night, through twilight and golden hour, to full day.
    static let keys: [Key] = [
        Key(altitude: -18, top: rgb(0x03050C), horizon: rgb(0x0A0F22), sun: rgb(0xFF8A4C), farHill: rgb(0x0B1020), nearHill: rgb(0x05070F)),
        Key(altitude: -10, top: rgb(0x080E2A), horizon: rgb(0x26204A), sun: rgb(0xFF8A4C), farHill: rgb(0x121328), nearHill: rgb(0x080912)),
        Key(altitude: -4, top: rgb(0x1A2758), horizon: rgb(0xB65A5E), sun: rgb(0xFF7A3C), farHill: rgb(0x2A2238), nearHill: rgb(0x120F1C)),
        Key(altitude: 0, top: rgb(0x34528F), horizon: rgb(0xF0935A), sun: rgb(0xFF9B48), farHill: rgb(0x46413F), nearHill: rgb(0x1E2219)),
        Key(altitude: 6, top: rgb(0x4580C2), horizon: rgb(0xFFD09A), sun: rgb(0xFFD27A), farHill: rgb(0x5A6B3E), nearHill: rgb(0x2B3B20)),
        Key(altitude: 20, top: rgb(0x2F6EBE), horizon: rgb(0x9CCBEF), sun: rgb(0xFFF1C2), farHill: rgb(0x4F7D45), nearHill: rgb(0x2C4A28)),
        Key(altitude: 60, top: rgb(0x1E5DB3), horizon: rgb(0x8EC3EF), sun: rgb(0xFFFBE8), farHill: rgb(0x4F8248), nearHill: rgb(0x2D4D29)),
    ]
}

private extension Double {
    var complement: Double { 1 - self }
}

/// Keeps the live sky between frames, with the place and weather it's for.
/// The place is guessed from the time zone until a real one is set.
@MainActor
final class LiveWeatherState {
    struct Frame {
        let sky: LiveSky
        let sun: SkyClock.Sun
        let moonPhase: Double
        let moonIllumination: Double
    }

    /// Where the sky is for, and its weather; set from outside as they're found.
    var place = SkyClock.Place.guess()
    var weather = LiveWeather.fair
    private var sky = LiveSky()
    private var lastFrame: Date?

    func update(feed: SpectrumFeed, at date: Date, forced: LiveWeatherDebug = .init()) -> Frame {
        let elapsed = lastFrame.map { date.timeIntervalSince($0) } ?? 0
        lastFrame = date
        let sun = forced.time.sun ?? SkyClock.sun(at: date, place: place)
        sky.update(energy: feed.energy, beat: feed.beat, sun: sun, weather: forced.weather.weather ?? weather, elapsed: elapsed)
        return Frame(sky: sky, sun: sun, moonPhase: SkyClock.moonPhase(at: date), moonIllumination: SkyClock.moonIllumination(at: date))
    }
}

/// Debug builds only: a weather and time of day to force, from the
/// visualizer's menu, to see each without waiting for it.
struct LiveWeatherDebug: Equatable {
    enum Weather: String, CaseIterable {
        case real, clear, partlyCloudy, cloudy, lightRain, downpour, thunderstorm, sleet, snow, fog

        var title: String {
            switch self {
            case .real: "Real Weather"
            case .clear: "Clear"
            case .partlyCloudy: "Partly Cloudy"
            case .cloudy: "Cloudy"
            case .lightRain: "Light Rain"
            case .downpour: "Downpour"
            case .thunderstorm: "Thunderstorm"
            case .sleet: "Sleet"
            case .snow: "Snow"
            case .fog: "Fog"
            }
        }

        var weather: LiveWeather? {
            switch self {
            case .real: nil
            case .clear: LiveWeather(symbolCode: "clearsky_day", cloudAreaFraction: nil, windSpeed: 2)
            case .partlyCloudy: LiveWeather(symbolCode: "partlycloudy_day", cloudAreaFraction: nil, windSpeed: 4)
            case .cloudy: LiveWeather(symbolCode: "cloudy", cloudAreaFraction: nil, windSpeed: 5)
            case .lightRain: LiveWeather(symbolCode: "lightrain", cloudAreaFraction: nil, windSpeed: 3)
            case .downpour: LiveWeather(symbolCode: "heavyrain", cloudAreaFraction: nil, windSpeed: 8)
            case .thunderstorm: LiveWeather(symbolCode: "heavyrainandthunder", cloudAreaFraction: nil, windSpeed: 10)
            case .sleet: LiveWeather(symbolCode: "sleet", cloudAreaFraction: nil, windSpeed: 6)
            case .snow: LiveWeather(symbolCode: "snow", cloudAreaFraction: nil, windSpeed: 4)
            case .fog: LiveWeather(symbolCode: "fog", cloudAreaFraction: nil, windSpeed: 1)
            }
        }
    }

    enum Time: String, CaseIterable {
        case real, dawn, sunrise, day, sunset, dusk, night

        var title: String {
            switch self {
            case .real: "Real Time"
            case .dawn: "Dawn"
            case .sunrise: "Sunrise"
            case .day: "Day"
            case .sunset: "Sunset"
            case .dusk: "Dusk"
            case .night: "Night"
            }
        }

        var sun: SkyClock.Sun? {
            switch self {
            case .real: nil
            case .dawn: SkyClock.Sun(altitude: -7, hourAngle: -100)
            case .sunrise: SkyClock.Sun(altitude: 3, hourAngle: -85)
            case .day: SkyClock.Sun(altitude: 40, hourAngle: -20)
            case .sunset: SkyClock.Sun(altitude: 3, hourAngle: 85)
            case .dusk: SkyClock.Sun(altitude: -7, hourAngle: 100)
            case .night: SkyClock.Sun(altitude: -30, hourAngle: 170)
            }
        }
    }

    var weather = Weather.real
    var time = Time.real
}
