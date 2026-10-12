import NavidromeCore
import SwiftUI

struct TransportControls: View {
    let engine: PlaybackEngine
    /// While dragging, the slider shows this instead of the engine's position.
    @State private var scrubPosition: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitleRow(
                title: engine.currentTitle ?? "Nothing queued",
                subtitle: engine.currentSubtitle
            )
            Text(statusText).font(.caption).foregroundStyle(statusColor)
            if engine.isLive {
                // A station has no length or position: say so instead of a progress bar.
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
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
                HStack {
                    Text(Self.format(scrubPosition ?? engine.position))
                    Spacer()
                    Text(Self.format(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            // Previous, play and next are centred under the progress bar; shuffle
            // and repeat sit at the edges as overlays so they don't pull them off centre.
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
                Button(engine.isShuffled ? "Shuffle On" : "Shuffle Off", systemImage: "shuffle") {
                    engine.toggleShuffle()
                }
                .foregroundStyle(engine.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .disabled(engine.isLive)
            }
            .overlay(alignment: .trailing) {
                Button(repeatLabel, systemImage: engine.repeatMode == .one ? "repeat.1" : "repeat") {
                    engine.cycleRepeatMode()
                }
                .foregroundStyle(engine.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .disabled(engine.isLive)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(engine.queue.isEmpty)
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
