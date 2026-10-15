import AppIntents
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
                    Text(engine.currentTitle ?? "Not Playing")
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
                .disabled(!engine.canGoNext)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title3)
        .padding(.horizontal)
    }
}

/// Full-screen player: artwork, controls, and the queue.
struct NowPlayingView: View {
    let model: AppModel
    let library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var isVisualizerOpen = false
    @State private var isLyricsOpen = false

    private var engine: PlaybackEngine { library.engine }

    private var savableQueue: [Song] {
        engine.queue.entries.map(\.song).filter { !$0.isLive }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ArtworkView(library: library, coverArtID: engine.queue.current?.song.coverArtID, side: 280)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                    TransportControls(engine: engine)
                    if let song = engine.queue.current?.song {
                        HStack(spacing: 32) {
                            // A station isn't on the server, so it can't be favorited or rated.
                            if !song.isLive {
                                MarkActions(library: library, target: .song(id: song.id), isStarred: song.isStarred, userRating: song.userRating)
                            }
                            AirPlayButton()
                                .frame(width: 32, height: 32)
                            Button("Lyrics", systemImage: "quote.bubble") { isLyricsOpen = true }
                            Button("Visualizer", systemImage: "waveform") { isVisualizerOpen = true }
                        }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        // Borderless, like the transport controls. With the default style a
                        // button in a list row is drawn in the text color instead of the
                        // accent, and takes taps anywhere in the row.
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                    }
                }
                .themedRows()
                Section {
                    QueueList(engine: engine)
                } header: {
                    HStack {
                        if let spinOff = engine.spinOff {
                            Label(spinOff.heading, systemImage: spinOff == .rated ? "hand.thumbsup" : "opticaldisc")
                                .lineLimit(1)
                        } else {
                            Text("Queue")
                        }
                        Spacer()
                        if engine.queue.hasNext {
                            Button("Clear Up Next") { engine.clearUpNext() }
                                .font(.subheadline)
                                .textCase(nil)
                        }
                    }
                }
                .themedRows()
            }
            .listStyle(.plain)
            .themedList()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "chevron.down") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    SleepTimerMenu(timer: library.sleepTimer)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis") {
                        if let song = engine.queue.current?.song {
                            SpinOffButton(library: library, song: song)
                            SongInfoButton(library: library, song: song)
                        }
                        Button("Save Queue as Playlist…", systemImage: "text.badge.plus") {
                            library.addToPlaylist.open(savableQueue, title: "Save Queue")
                        }
                        // A station can't go in a playlist.
                        .disabled(savableQueue.isEmpty)
                    }
                }
            }
            .addToPlaylistSheet(library)
            .infoSheet(library)
            .playlistConfirmation(library.playlistEditor)
            .noticeBanner(library.spinOff.notice, seconds: 5) { library.spinOff.dismissNotice() }
            .fullScreenCover(isPresented: $isVisualizerOpen) {
                VisualizerView(model: model, engine: engine)
            }
            .fullScreenCover(isPresented: $isLyricsOpen) {
                LyricsView(library: library)
            }
            // Tells Siri which song this screen is about ("add this to my
            // running playlist").
            .userActivity("com.erichebert.musicapp.nowPlaying", isActive: engine.queue.current.map { !$0.song.isLive } ?? false) { activity in
                guard let song = engine.queue.current?.song, !song.isLive else { return }
                activity.title = song.title
                activity.appEntityIdentifier = EntityIdentifier(for: SongEntity.self, identifier: song.id)
            }
        }
    }
}
