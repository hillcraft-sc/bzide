import NavidromeCore
import SwiftUI

/// The strip above the tab bar: what's playing, play/pause, next. Tapping it
/// opens Now Playing.
struct MiniPlayer: View {
    let library: Library
    let open: () -> Void

    private var engine: PlaybackEngine { library.engine }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    ArtworkView(library: library, coverArtID: engine.queue.current?.song.coverArtID, side: 32)
                    Text(engine.queue.current?.song.title ?? "Not Playing")
                        .lineLimit(1)
                        .foregroundStyle(engine.queue.isEmpty ? .secondary : .primary)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(engine.queue.isEmpty)

            Button(engine.status.isActive ? "Pause" : "Play",
                   systemImage: engine.status.isActive ? "pause.fill" : "play.fill") {
                engine.togglePlayPause()
            }
            .disabled(engine.queue.isEmpty)
            Button("Next", systemImage: "forward.fill") { engine.next() }
                .disabled(!engine.queue.hasNext)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title3)
        .padding(.horizontal)
    }
}

/// Full-screen player: artwork, controls, and the queue.
struct NowPlayingView: View {
    let library: Library
    @Environment(\.dismiss) private var dismiss

    private var engine: PlaybackEngine { library.engine }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ArtworkView(library: library, coverArtID: engine.queue.current?.song.coverArtID, side: 280)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                    TransportControls(engine: engine)
                    if let song = engine.queue.current?.song {
                        HStack {
                            StarButton(stars: library.stars, target: .song(id: song.id), fromServer: song.isStarred)
                        }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                    }
                }
                Section("Queue") {
                    QueueList(engine: engine)
                }
            }
            .listStyle(.plain)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "chevron.down") { dismiss() }
                }
            }
        }
    }
}
