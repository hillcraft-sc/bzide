import AVFAudio
import NavidromeCore
import SwiftUI

/// Full-screen spectrum bars in the theme's accent, following what's playing.
/// The audio tap runs only while this is open, and the screen stays awake.
/// Radio and AirPlay can't be analysed (see docs/BEHAVIOR.md), so they get a
/// message instead.
struct VisualizerView: View {
    let model: AppModel
    let engine: PlaybackEngine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var accent
    @State private var feed: SpectrumFeed
    @State private var isOnAirPlay = Self.isRoutedToAirPlay()
    /// What metering was before opening, put back on close (the debug switch may have it on).
    @State private var meteringBefore = false

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
                bars
            }
            VStack {
                HStack {
                    Button("Close", systemImage: "chevron.down") { dismiss() }
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .padding(12)
                        .contentShape(.rect)
                    Spacer()
                }
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
                    .padding(.bottom, 24)
                }
            }
            .tint(.white)
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

    /// Bars across the width, growing up from the bottom, redrawn every frame.
    private var bars: some View {
        let color = accent ?? Color(uiColor: .tintColor)
        return TimelineView(.animation) { timeline in
            let levels = feed.update(at: timeline.date)
            Canvas { context, size in
                guard !levels.isEmpty else { return }
                let gap: CGFloat = 3
                let width = (size.width - gap * CGFloat(levels.count - 1)) / CGFloat(levels.count)
                let maxHeight = size.height * 0.7
                for (index, level) in levels.enumerated() {
                    // A sliver even in silence, so the bars read as a meter.
                    let height = max(CGFloat(level) * maxHeight, 2)
                    let rect = CGRect(
                        x: CGFloat(index) * (width + gap),
                        y: size.height - height,
                        width: width,
                        height: height
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: min(width / 2, 3)), with: .color(color))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 110)
            .padding(.top, 80)
        }
        .accessibilityLabel("Spectrum visualizer")
    }

    private static func isRoutedToAirPlay() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
    }
}
