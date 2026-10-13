import NavidromeCore
import SwiftUI

/// The song's title and artist, centered, for full-screen players drawn over
/// artwork or a visualization (the visualizer, lyrics).
struct OverlayTitle: View {
    let engine: PlaybackEngine
    /// The text color: white over dark backgrounds.
    var ink: Color = .white

    var body: some View {
        if let title = engine.currentTitle {
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
}

/// Previous, play/pause and next, as in Now Playing, for the same screens.
/// Play/pause is a solid circle in the ink with the icon cut out of it.
struct OverlayTransport: View {
    let engine: PlaybackEngine
    var ink: Color = .white
    /// The color of the play/pause icon on its circle.
    var iconOnCircle: Color = .black

    var body: some View {
        HStack(spacing: 48) {
            Button("Previous", systemImage: "backward.fill") { engine.previous() }
                .font(.title)
                .disabled(engine.isLive || engine.queue.isEmpty)
            Button(engine.status.isActive ? "Pause" : "Play",
                   systemImage: engine.status.isActive ? "pause.fill" : "play.fill") {
                engine.togglePlayPause()
            }
            .font(.title)
            .foregroundStyle(iconOnCircle)
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
}
