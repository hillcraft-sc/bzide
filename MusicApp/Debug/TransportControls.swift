import NavidromeCore
import SwiftUI

struct TransportControls: View {
    let engine: PlaybackEngine
    /// While dragging, the slider shows this instead of the engine's position.
    @State private var scrubPosition: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitleRow(
                title: engine.queue.current?.song.title ?? "Nothing queued",
                subtitle: engine.queue.current?.song.artist
            )
            Text(statusText).font(.caption).foregroundStyle(statusColor)

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

            HStack {
                Spacer()
                Button("Previous", systemImage: "backward.fill") { engine.previous() }
                Spacer()
                Button(engine.status.isActive ? "Pause" : "Play",
                       systemImage: engine.status.isActive ? "pause.fill" : "play.fill") {
                    engine.togglePlayPause()
                }
                .font(.largeTitle)
                Spacer()
                Button("Next", systemImage: "forward.fill") { engine.next() }
                    .disabled(!engine.queue.hasNext)
                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(engine.queue.isEmpty)
        }
        .padding(.vertical, 4)
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
