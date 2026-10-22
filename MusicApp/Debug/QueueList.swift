import NavidromeCore
import SwiftUI

/// The current song, then what plays next. Upcoming songs can be swiped away
/// or dragged into a new order; the current one stays put, so editing the
/// queue never changes what's playing. A long-press offers Song Info and the
/// way to the song's album and artist.
struct QueueList: View {
    let engine: PlaybackEngine
    /// For the long-press menu; the debug player has none.
    var library: Library?

    var body: some View {
        if let current = engine.queue.current {
            row(current, isCurrent: true)
        } else {
            Text("Empty").foregroundStyle(.secondary)
        }
        ForEach(engine.queue.upNext) { entry in
            row(entry, isCurrent: false)
                .swipeActions {
                    Button("Remove", systemImage: "minus.circle", role: .destructive) {
                        engine.removeFromQueue(entry.id)
                    }
                }
        }
        .onMove { offsets, destination in
            engine.moveUpcoming(fromOffsets: offsets, toOffset: destination)
        }
    }

    private func row(_ entry: QueueEntry, isCurrent: Bool) -> some View {
        Button {
            engine.jump(to: entry.id)
        } label: {
            HStack {
                TitleRow(title: entry.song.title, subtitle: entry.song.artist)
                Spacer()
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Current")
                }
            }
        }
        .foregroundStyle(.primary)
        // A station has nothing to go to or look up.
        .contextMenu {
            if let library, !entry.song.isLive {
                SongInfoButton(library: library, song: entry.song)
                Section {
                    SongGoToLinks(song: entry.song)
                }
            }
        }
        .siriEntity(songID: entry.song.isLive ? nil : entry.song.id)
    }
}
