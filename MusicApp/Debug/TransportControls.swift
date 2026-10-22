import NavidromeCore
import SwiftUI

struct TransportControls: View {
    let engine: PlaybackEngine
    /// Shows whether the equalizer is heard; the debug player has none.
    var equalizer: EqualizerModel?
    /// While dragging, the slider shows this instead of the engine's position.
    @State private var scrubPosition: TimeInterval?

    /// How far a VoiceOver swipe on the position moves.
    static let accessibilitySeekStep: TimeInterval = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitleRow(
                title: engine.currentTitle ?? "Nothing queued",
                subtitle: engine.currentSubtitle
            )
            HStack {
                Text(statusText).foregroundStyle(statusColor)
                Spacer()
                if let quality = engine.currentQuality {
                    QualityLabel(quality: quality)
                }
                if let equalizer {
                    EqualizerBadge(equalizer: equalizer, engine: engine)
                }
            }
            .font(.caption)
            if engine.isLive {
                // A station has no length or position: say so instead of a progress bar.
                Label("Live", systemImage: "headphones.sensor.tag.radiowaves.left.and.right")  // dot.radiowaves.left.and.right
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
            }

            if let duration = engine.duration, duration > 0 {
                Slider(
                    value: Binding(
                        get: { scrubPosition ?? engine.position },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...duration
                ) { editing in
                    if !editing, let target = scrubPosition {
                        engine.seek(to: target)
                        scrubPosition = nil
                    }
                }
                // VoiceOver reads the time, not a percentage, and its swipes
                // seek (they don't end a drag, so they'd change nothing).
                .accessibilityLabel("Position")
                .accessibilityValue("\(Self.format(engine.position)) of \(Self.format(duration))")
                .accessibilityAdjustableAction { direction in
                    let step: TimeInterval = direction == .increment ? Self.accessibilitySeekStep : -Self.accessibilitySeekStep
                    engine.seek(to: min(max(engine.position + step, 0), duration))
                }
                HStack {
                    Text(Self.format(scrubPosition ?? engine.position))
                    Spacer()
                    Text(Self.format(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            // Previous, play and next are centered under the progress bar; shuffle
            // and repeat sit at the edges as overlays so they don't pull them off center.
            // A radio station can't be shuffled or repeated, so they're hidden for one.
            HStack(spacing: 44) {
                Button("Previous", systemImage: "backward.fill") { engine.previous() }
                    .disabled(engine.isLive)
                Button(engine.status.isActive ? "Pause" : "Play",
                       systemImage: engine.status.isActive ? "pause.fill" : "play.fill") {
                    engine.togglePlayPause()
                }
                .font(.largeTitle)
                Button("Next", systemImage: "forward.fill") { engine.next() }
                    .disabled(!engine.canGoNext)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                if !engine.isLive {
                    Button(engine.isShuffled ? "Shuffle On" : "Shuffle Off", systemImage: "shuffle") {
                        engine.toggleShuffle()
                    }
                    .foregroundStyle(engine.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            }
            .overlay(alignment: .trailing) {
                if !engine.isLive {
                    Button(repeatLabel, systemImage: engine.repeatMode == .one ? "repeat.1" : "repeat") {
                        engine.cycleRepeatMode()
                    }
                    .foregroundStyle(engine.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(engine.queue.isEmpty)
            // The controls grow with the text only up to the largest standard
            // size: beyond it, five big icons collide across a phone.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(.vertical, 4)
    }

    private var repeatLabel: String {
        switch engine.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    private var statusText: String {
        switch engine.status {
        case .idle: "Idle"
        case .paused: "Paused"
        case .buffering: "Buffering…"
        case .playing: "Playing"
        case .reconnecting: "Reconnecting…"
        case .failed(let message): "Failed: \(message)"
        }
    }

    private var statusColor: Color {
        switch engine.status {
        case .failed: .red
        case .reconnecting: .orange
        default: .secondary
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}

/// The current song's format, bitrate and source. Tapping it hides it behind a
/// small icon, and tapping the icon shows it again; the choice is remembered.
private struct QualityLabel: View {
    let quality: PlaybackQuality
    /// A display preference for this device only.
    @AppStorage("showsPlaybackQuality") private var isShown = true

    var body: some View {
        Button {
            withAnimation(.snappy) { isShown.toggle() }
        } label: {
            if isShown {
                Text(quality.label)
                    .monospacedDigit()
                    .lineLimit(1)
                    .transition(.opacity)
            } else {
                Image(systemName: "waveform")
                    .transition(.opacity)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel(isShown ? "Quality: \(quality.label)" : "Show quality")
        .accessibilityHint(isShown ? "Hides the quality" : "")
    }
}
