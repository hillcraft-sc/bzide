import AVFAudio
import NavidromeCore
import SwiftUI

/// Full-screen visualizer following what's playing: spectrum bars or the sound
/// wave, in the theme's accent or in many colors. Swipe to change style, or
/// pick style and colors from the menu at the top; both are remembered.
/// Playback controls at the bottom work without leaving it.
///
/// The audio tap measures only while this is open, and the screen stays awake.
/// Radio and AirPlay can't be analyzed (see docs/BEHAVIOR.md), so they get a
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
    /// The Catppuccin accents chosen for Custom, as comma-separated names.
    @AppStorage("visualizerCustomColors") private var customColorNames = VisualizerPalette.defaultCustom
    @State private var isChoosingColors = false
    @State private var grooveState = GrooveState()
    @State private var tapestryState = TapestryState()
    @State private var weatherState = WeatherState()
    @State private var chromeState = ChromeState()
    @State private var typesetState = TypesetState()
    @State private var polygraphState = PolygraphState()

    init(model: AppModel, engine: PlaybackEngine) {
        self.model = model
        self.engine = engine
        _feed = State(initialValue: SpectrumFeed(meter: model.levelMeter))
    }

    var body: some View {
        GeometryReader { geometry in
            // Sideways, the controls move to a panel on the right so the
            // visualization can use the full height.
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if let message = unavailableMessage {
                    ContentUnavailableView(message, systemImage: "waveform.slash")
                        .foregroundStyle(.white)
                } else {
                    visualization(landscape: landscape)
                        .contentShape(.rect)
                        .gesture(swipeToChangeStyle)
                }
                overlay(landscape: landscape)
            }
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

    /// Custom is for Catppuccin's accents; in the other themes it shows as Multicolor.
    private var effectiveMode: VisualizerColorMode {
        colorMode == .custom && palette == nil ? .multicolor : colorMode
    }

    private var customAccents: [CatppuccinAccent] {
        VisualizerPalette.accents(from: customColorNames)
    }

    private func colors(_ count: Int) -> [Color] {
        VisualizerPalette.colors(count: count, mode: effectiveMode, accent: accent, catppuccin: palette, custom: customAccents)
    }

    // MARK: - Drawing

    /// The space left for drawing, around the menu at the top and the title
    /// and controls (below in portrait, in a side panel in landscape).
    private func drawingInsets(landscape: Bool) -> EdgeInsets {
        landscape
            ? EdgeInsets(top: 56, leading: 16, bottom: 16, trailing: Self.sidePanelWidth + 16)
            : EdgeInsets(top: 105, leading: 12, bottom: 230, trailing: 12)
    }

    static let sidePanelWidth: CGFloat = 260

    /// Polygraph's white paper fills the screen, so the controls over it
    /// are drawn in dark ink instead of white.
    private var isOnPaper: Bool {
        style == .polygraph && unavailableMessage == nil
    }

    /// The color for text and buttons over the visualization.
    private var ink: Color {
        isOnPaper ? Color(white: 0.12) : .white
    }

    private func visualization(landscape: Bool) -> some View {
        TimelineView(.animation) { timeline in
            let levels = feed.update(at: timeline.date)
            switch style {
            case .plasma:
                plasma(flow: feed.flow, beat: feed.beat, energy: feed.energy, landscape: landscape)
            case .livingCover:
                LivingCoverView(
                    library: model.library, coverArtID: engine.queue.current?.song.coverArtID,
                    levels: levels, energy: feed.energy, beat: feed.beat,
                    colors: effectiveMode == .accent ? [accent] : colors(8),
                    insets: drawingInsets(landscape: landscape)
                )
            case .groove:
                GrooveView(
                    engine: engine, library: model.library, feed: feed, date: timeline.date,
                    colors: effectiveMode == .accent ? [accent] : colors(24), state: grooveState
                )
                .padding(drawingInsets(landscape: landscape))
            case .tapestry:
                TapestryView(
                    engine: engine, feed: feed, date: timeline.date,
                    colors: colors(TapestryRecorder.threadCount), state: tapestryState
                )
                .padding(drawingInsets(landscape: landscape))
            case .weather:
                WeatherView(
                    feed: feed, date: timeline.date, colors: fourColors,
                    insets: drawingInsets(landscape: landscape), landscape: landscape, state: weatherState
                )
            case .chrome:
                ChromeView(
                    library: model.library, coverArtID: engine.queue.current?.song.coverArtID,
                    levels: levels, beat: feed.beat, date: timeline.date, colors: fourColors, state: chromeState
                )
                .padding(drawingInsets(landscape: landscape))
            case .typeset:
                TypesetView(
                    title: engine.currentTitle ?? "", artist: engine.currentSubtitle,
                    levels: levels, energy: feed.energy, beat: feed.beat, date: timeline.date,
                    colors: effectiveMode == .accent ? [accent] : colors(24),
                    insets: drawingInsets(landscape: landscape), state: typesetState
                )
            case .polygraph:
                PolygraphView(
                    engine: engine, feed: feed, levels: levels, date: timeline.date,
                    colors: effectiveMode == .accent ? [accent] : colors(4),
                    insets: drawingInsets(landscape: landscape), landscape: landscape, state: polygraphState
                )
            case .bars, .waveform:
                let wave = feed.wave
                Canvas { context, size in
                    if style == .bars {
                        drawBars(levels, in: &context, size: size)
                    } else {
                        drawWave(wave, in: &context, size: size)
                    }
                }
                .padding(drawingInsets(landscape: landscape))
            }
        }
        .accessibilityLabel("\(style.title) visualizer")
        .accessibilityHint("Swipe left or right to change style")
    }

    /// The Plasma shader (Plasma.metal) over the whole screen, behind the controls.
    private func plasma(flow: Double, beat: Float, energy: SpectrumEnergy, landscape: Bool) -> some View {
        let colors = fourColors
        // Wrapped so the shader's single-precision maths stays smooth for hours.
        let flow = Float(flow.truncatingRemainder(dividingBy: 10_000))
        return GeometryReader { geometry in
            Rectangle()
                .colorEffect(ShaderLibrary.plasma(
                    .float2(geometry.size),
                    .float(flow),
                    .float(beat), .float(energy.bass), .float(energy.mid), .float(energy.treble),
                    .color(colors[0]), .color(colors[1]), .color(colors[2]), .color(colors[3])
                ))
        }
        // Darker where the controls are (top and bottom, or the right-hand
        // panel sideways), so the white text and buttons stay readable.
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.18),
                    .init(color: .clear, location: 0.55),
                    .init(color: .black.opacity(0.7), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(landscape ? 0 : 1)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.75), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .opacity(landscape ? 1 : 0)
        }
        .ignoresSafeArea()
    }

    /// Four colors for Plasma's palette loop, Weather's sky and hills, and
    /// the light on Chrome's edges:
    /// shades of the accent, or four from the multicolor sweep.
    private var fourColors: [Color] {
        switch effectiveMode {
        case .multicolor, .custom:
            return colors(4)
        case .accent:
            let base = UIColor(accent)
            return [
                Color(base.mixed(with: .black, amount: 0.8)),
                accent,
                Color(base.mixed(with: .white, amount: 0.55)),
                Color(base.mixed(with: .black, amount: 0.35)),
            ]
        }
    }

    /// Bars across the width, growing up from the bottom, bass on the left.
    private func drawBars(_ levels: [Float], in context: inout GraphicsContext, size: CGSize) {
        guard !levels.isEmpty else { return }
        let colors = colors(levels.count)
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
        switch effectiveMode {
        case .accent:
            shading = .color(accent)
        case .multicolor, .custom:
            shading = .linearGradient(Gradient(colors: colors(16)), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
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

    private func overlay(landscape: Bool) -> some View {
        VStack {
            ZStack {
                styleMenu
                HStack {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(ink.opacity(isOnPaper ? 0.08 : 0.15), in: .circle)
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, landscape ? 8 : 12)
            if landscape {
                // Title and controls in a panel on the right, vertically centered.
                HStack {
                    Spacer()
                    VStack(spacing: 20) {
                        nowPlayingTitle
                        controls
                    }
                    .frame(width: Self.sidePanelWidth)
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer()
                nowPlayingTitle
                controls
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
        }
        .tint(ink)
        // On the paper, a halo of paper around the text and buttons keeps
        // them clear of the ink running underneath.
        .shadow(color: isOnPaper ? PolygraphView.paper : .clear, radius: 3)
        .shadow(color: isOnPaper ? PolygraphView.paper : .clear, radius: 6)
    }

    /// Not on Typeset, which is the title already.
    @ViewBuilder
    private var nowPlayingTitle: some View {
        if let title = engine.currentTitle, style != .typeset {
            VStack(spacing: 2) {
                Text(title).font(.headline)
                if let subtitle = engine.currentSubtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(ink.opacity(0.7))
                }
            }
            .foregroundStyle(ink)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
    }

    /// The current style's icon and name; opens the choice of style and colors.
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
            Section("Colors") {
                Picker("Colors", selection: $colorMode) {
                    // Custom picks from Catppuccin's accents, so only in its themes.
                    ForEach(palette == nil ? [.accent, .multicolor] : VisualizerColorMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                if palette != nil {
                    Button("Choose Custom Colors…", systemImage: "slider.horizontal.3") {
                        isChoosingColors = true
                    }
                }
            }
        } label: {
            Label(style.title, systemImage: style.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(ink.opacity(isOnPaper ? 0.08 : 0.15), in: .capsule)
        }
        .accessibilityHint("Choose the style and colors")
        .sheet(isPresented: $isChoosingColors) {
            if let palette {
                CustomColorsSheet(palette: palette, names: $customColorNames) {
                    colorMode = .custom
                }
            }
        }
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
            .foregroundStyle(isOnPaper ? .white : .black)
            .frame(width: 72, height: 72)
            .background(ink, in: .circle)
            .disabled(engine.queue.isEmpty)
            Button("Next", systemImage: "forward.fill") { engine.next() }
                .font(.title)
                .disabled(!engine.canGoNext)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(ink)
    }

    private static func isRoutedToAirPlay() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
    }
}

enum VisualizerStyle: String, CaseIterable {
    case bars, waveform, plasma, polygraph, groove, livingCover, tapestry, weather, chrome, typeset

    var title: String {
        switch self {
        case .bars: "Bars"
        case .waveform: "Waveform"
        case .plasma: "Plasma"
        case .polygraph: "Polygraph"
        case .groove: "Groove"
        case .livingCover: "Living Cover"
        case .tapestry: "Tapestry"
        case .weather: "Weather"
        case .chrome: "Chrome"
        case .typeset: "Typeset"
        }
    }

    var symbol: String {
        switch self {
        case .bars: "chart.bar.fill"
        case .waveform: "waveform.path"
        case .plasma: "flame"
        case .polygraph: "waveform.path.ecg.rectangle"
        case .groove: "opticaldisc"
        case .livingCover: "square.grid.3x3.fill"
        case .tapestry: "scribble.variable"
        case .weather: "cloud.bolt.rain.fill"
        case .chrome: "drop.fill"
        case .typeset: "textformat.size"
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
    case accent, multicolor, custom

    var title: String {
        switch self {
        case .accent: "Accent"
        case .multicolor: "Multicolor"
        case .custom: "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .accent: "circle.fill"
        case .multicolor: "paintpalette"
        case .custom: "swatchpalette"
        }
    }
}

/// Picks which Catppuccin accents Custom uses, at least two, shown in the
/// current flavor. They're always used in palette order.
private struct CustomColorsSheet: View {
    let palette: CatppuccinPalette
    @Binding var names: String
    /// Called on Done, to switch the visualizer to Custom.
    let done: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var chosen: [CatppuccinAccent] { VisualizerPalette.accents(from: names) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SwatchGrid(
                        options: CatppuccinAccent.allCases,
                        color: { Color(palette.accent($0)) },
                        title: \.title,
                        isSelected: { chosen.contains($0) },
                        checkmark: Color(palette.base),
                        choose: toggle
                    )
                    .padding(.vertical, 6)
                } footer: {
                    Text("The visualizer blends the chosen colors in this order. Choose at least two.")
                }
                .themedRows(grouped: true)
            }
            .themedList(grouped: true)
            .navigationTitle("Custom Colors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        done()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func toggle(_ accent: CatppuccinAccent) {
        var set = Set(chosen)
        if set.contains(accent) {
            // Blending needs two colors; the last two stay.
            guard set.count > 2 else { return }
            set.remove(accent)
        } else {
            set.insert(accent)
        }
        names = VisualizerPalette.names(of: set)
    }
}

/// The colors a visualizer draws with, left to right.
enum VisualizerPalette {
    /// Accent: the accent throughout. Multicolor: in a Catppuccin theme, its 14
    /// accents in palette order, blended across; otherwise a sweep of hues
    /// starting from the accent (blue → purple → pink → orange for iOS blue).
    /// Custom: the chosen Catppuccin accents, blended the same way.
    static func colors(
        count: Int, mode: VisualizerColorMode, accent: Color, catppuccin: CatppuccinPalette?, custom: [CatppuccinAccent] = []
    ) -> [Color] {
        guard count > 0 else { return [] }
        guard mode != .accent else { return Array(repeating: accent, count: count) }
        if let catppuccin {
            let chosen = mode == .custom && custom.count >= 2 ? custom : CatppuccinAccent.allCases
            let accents = chosen.map { catppuccin.accent($0) }
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

    /// A warm-to-cool mix to start Custom from.
    static let defaultCustom = names(of: [.mauve, .pink, .peach, .teal, .blue])

    /// Saved names to accents, in palette order; unknown names are ignored.
    static func accents(from names: String) -> [CatppuccinAccent] {
        let set = Set(names.split(separator: ",").compactMap { CatppuccinAccent(rawValue: String($0)) })
        return CatppuccinAccent.allCases.filter(set.contains)
    }

    static func names(of accents: Set<CatppuccinAccent>) -> String {
        CatppuccinAccent.allCases.filter(accents.contains).map(\.rawValue).joined(separator: ",")
    }

    /// The color `position` (0...1) of the way along `colors`, mixed between neighbors.
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

private extension UIColor {
    /// This color moved `amount` (0...1) of the way toward `other`.
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * amount,
            green: g1 + (g2 - g1) * amount,
            blue: b1 + (b2 - b1) * amount,
            alpha: a1 + (a2 - a1) * amount
        )
    }
}
