import AVFAudio
import NavidromeCore
import SwiftUI

/// Full-screen visualizer following what's playing: spectrum bars or the sound
/// wave, in the theme's accent or in many colours. Swipe to change style, or
/// pick style and colours from the menu at the top; both are remembered.
/// Playback controls at the bottom work without leaving it.
///
/// The audio tap measures only while this is open, and the screen stays awake.
/// Radio and AirPlay can't be analysed (see docs/BEHAVIOR.md), so they get a
/// message instead.
struct VisualizerView: View {
    let model: AppModel
    let engine: PlaybackEngine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var themeAccent
    @Environment(\.catppuccin) private var palette
    @State private var feed: SpectrumFeed
    @State private var isOnAirPlay = Self.isRoutedToAirPlay()
    /// What metering was before opening, put back on close (the debug switch may have it on).
    @State private var meteringBefore = false
    /// Display preferences for this device.
    @AppStorage("visualizerStyle") private var style = VisualizerStyle.bars
    @AppStorage("visualizerColors") private var colorMode = VisualizerColorMode.accent

    init(model: AppModel, engine: PlaybackEngine) {
        self.model = model
        self.engine = engine
        _feed = State(initialValue: SpectrumFeed(meter: model.levelMeter))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let message = unavailableMessage {
                ContentUnavailableView(message, systemImage: "waveform.slash")
                    .foregroundStyle(.white)
            } else {
                visualization
                    .contentShape(.rect)
                    .gesture(swipeToChangeStyle)
            }
            overlay
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            meteringBefore = model.isMetering
            model.isMetering = true
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            model.isMetering = meteringBefore
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            isOnAirPlay = Self.isRoutedToAirPlay()
        }
    }

    private var unavailableMessage: String? {
        if engine.isLive { return "The visualizer isn't available for radio." }
        if isOnAirPlay { return "The visualizer isn't available over AirPlay." }
        return nil
    }

    private var accent: Color {
        themeAccent ?? Color(uiColor: .tintColor)
    }

    // MARK: - Drawing

    private var visualization: some View {
        TimelineView(.animation) { timeline in
            let levels = feed.update(at: timeline.date)
            let wave = feed.wave
            Canvas { context, size in
                switch style {
                case .bars: drawBars(levels, in: &context, size: size)
                case .waveform: drawWave(wave, in: &context, size: size)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 230)
            .padding(.top, 100)
        }
        .accessibilityLabel(style == .bars ? "Spectrum visualizer" : "Waveform visualizer")
        .accessibilityHint("Swipe left or right to change style")
    }

    /// Bars across the width, growing up from the bottom, bass on the left.
    private func drawBars(_ levels: [Float], in context: inout GraphicsContext, size: CGSize) {
        guard !levels.isEmpty else { return }
        let colors = VisualizerPalette.colors(count: levels.count, mode: colorMode, accent: accent, catppuccin: palette)
        let gap: CGFloat = 3
        let width = (size.width - gap * CGFloat(levels.count - 1)) / CGFloat(levels.count)
        let maxHeight = size.height * 0.85
        for (index, level) in levels.enumerated() {
            // A sliver even in silence, so the bars read as a meter.
            let height = max(CGFloat(level) * maxHeight, 2)
            let rect = CGRect(x: CGFloat(index) * (width + gap), y: size.height - height, width: width, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: min(width / 2, 3)), with: .color(colors[index]))
        }
    }

    /// The sound wave as a line across the middle, with a soft glow.
    private func drawWave(_ wave: [Float], in context: inout GraphicsContext, size: CGSize) {
        guard wave.count > 1 else { return }
        let middle = size.height / 2
        let amplitude = size.height * 0.4
        var path = Path()
        for (index, value) in wave.enumerated() {
            let point = CGPoint(
                x: size.width * CGFloat(index) / CGFloat(wave.count - 1),
                y: middle - CGFloat(value) * amplitude
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        let shading: GraphicsContext.Shading
        switch colorMode {
        case .accent:
            shading = .color(accent)
        case .multicolor:
            let colors = VisualizerPalette.colors(count: 16, mode: .multicolor, accent: accent, catppuccin: palette)
            shading = .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
        }
        var glow = context
        glow.opacity = 0.3
        glow.stroke(path, with: shading, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: shading, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Controls

    private var swipeToChangeStyle: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { drag in
            guard abs(drag.translation.width) > 50, abs(drag.translation.width) > abs(drag.translation.height) else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                style = drag.translation.width < 0 ? style.next : style.previous
            }
        }
    }

    private var overlay: some View {
        VStack {
            ZStack {
                styleMenu
                HStack {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.15), in: .circle)
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            Spacer()
            if let title = engine.currentTitle {
                VStack(spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle = engine.currentSubtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal)
            }
            controls
                .padding(.top, 16)
                .padding(.bottom, 32)
        }
        .tint(.white)
    }

    /// The current style's icon and name; opens the choice of style and colours.
    private var styleMenu: some View {
        Menu {
            Section("Style") {
                Picker("Style", selection: $style) {
                    ForEach(VisualizerStyle.allCases, id: \.self) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.inline)
            }
            Section("Colours") {
                Picker("Colours", selection: $colorMode) {
                    ForEach(VisualizerColorMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label(style.title, systemImage: style.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.white.opacity(0.15), in: .capsule)
        }
        .accessibilityHint("Choose the style and colours")
    }

    /// Previous, play/pause and next, as in Now Playing.
    private var controls: some View {
        HStack(spacing: 48) {
            Button("Previous", systemImage: "backward.fill") { engine.previous() }
                .font(.title)
                .disabled(engine.isLive || engine.queue.isEmpty)
            Button(engine.status.isActive ? "Pause" : "Play",
                   systemImage: engine.status.isActive ? "pause.fill" : "play.fill") {
                engine.togglePlayPause()
            }
            .font(.title)
            .foregroundStyle(.black)
            .frame(width: 72, height: 72)
            .background(.white, in: .circle)
            .disabled(engine.queue.isEmpty)
            Button("Next", systemImage: "forward.fill") { engine.next() }
                .font(.title)
                .disabled(!engine.canGoNext)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
    }

    private static func isRoutedToAirPlay() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
    }
}

enum VisualizerStyle: String, CaseIterable {
    case bars, waveform

    var title: String {
        switch self {
        case .bars: "Bars"
        case .waveform: "Waveform"
        }
    }

    var symbol: String {
        switch self {
        case .bars: "chart.bar.fill"
        case .waveform: "waveform.path"
        }
    }

    var next: VisualizerStyle {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }

    var previous: VisualizerStyle {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) - 1 + all.count) % all.count]
    }
}

enum VisualizerColorMode: String, CaseIterable {
    case accent, multicolor

    var title: String {
        switch self {
        case .accent: "Accent"
        case .multicolor: "Multicolor"
        }
    }

    var symbol: String {
        switch self {
        case .accent: "circle.fill"
        case .multicolor: "paintpalette"
        }
    }
}

/// The colours a visualizer draws with, left to right.
enum VisualizerPalette {
    /// Accent: the accent throughout. Multicolor: in a Catppuccin theme, its 14
    /// accents in palette order, blended across; otherwise a sweep of hues
    /// starting from the accent (blue → purple → pink → orange for iOS blue).
    static func colors(count: Int, mode: VisualizerColorMode, accent: Color, catppuccin: CatppuccinPalette?) -> [Color] {
        guard count > 0 else { return [] }
        guard mode == .multicolor else { return Array(repeating: accent, count: count) }
        if let catppuccin {
            let accents = CatppuccinAccent.allCases.map { catppuccin.accent($0) }
            return (0..<count).map { index in
                blend(accents, at: count == 1 ? 0 : Double(index) / Double(count - 1))
            }
        }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(accent).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return (0..<count).map { index in
            let position = count == 1 ? 0 : CGFloat(index) / CGFloat(count - 1)
            let shifted = (hue + 0.55 * position).truncatingRemainder(dividingBy: 1)
            return Color(hue: shifted, saturation: 0.7, brightness: 0.95)
        }
    }

    /// The colour `position` (0...1) of the way along `colors`, mixed between neighbours.
    private static func blend(_ colors: [RGBColor], at position: Double) -> Color {
        let scaled = position * Double(colors.count - 1)
        let low = min(Int(scaled), colors.count - 1)
        let high = min(low + 1, colors.count - 1)
        let mix = scaled - Double(low)
        let (a, b) = (colors[low], colors[high])
        return Color(
            red: a.red + (b.red - a.red) * mix,
            green: a.green + (b.green - a.green) * mix,
            blue: a.blue + (b.blue - a.blue) * mix
        )
    }
}
