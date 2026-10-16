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
    /// The saved stations, loaded while a dialed station plays, so Save
    /// Station shows only for one that isn't saved.
    @State private var savedStations: RadioStationsModel?
    /// The dialed station saved from here, which then reads "Saved".
    @State private var savedSongID: String?

    private var engine: PlaybackEngine { library.engine }

    /// For a dialed station, once the saved stations have loaded: whether
    /// it's saved (just now here, or already), or can be.
    private func saveState(_ song: Song) -> SaveStationButton.Status? {
        guard SpinTheDialModel.isDialed(song), let savedStations, case .loaded = savedStations.state,
              let savable = library.spinTheDial.savable(song) else { return nil }
        if savedSongID == song.id { return .justSaved }
        return savedStations.contains(stream: savable.stream) ? .alreadySaved : .unsaved
    }

    private var savableQueue: [Song] {
        engine.queue.entries.map(\.song).filter { !$0.isLive }
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis") {
            if let song = engine.queue.current?.song {
                SpinOffButton(library: library, song: song)
                SongInfoButton(library: library, song: song)
            }
            Button("Save Queue as Playlist…", systemImage: "text.badge.plus") {
                library.addToPlaylist.open(savableQueue, title: "Save Queue")
            }
            .disabled(savableQueue.isEmpty)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ArtworkView(library: library, coverArtID: engine.queue.current?.song.coverArtID, side: 280)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                    TransportControls(engine: engine)
                    // The song a station is playing, when it's in the library.
                    if engine.isLive, let match = library.onAir.match {
                        InYourLibraryBadge(library: library, song: match)
                            .listRowSeparator(.hidden)
                    }
                    if let song = engine.queue.current?.song {
                        HStack(spacing: 32) {
                            // A station isn't on the server, so it can't be favorited or
                            // rated, and has no lyrics or levels for the visualizer.
                            if !song.isLive {
                                MarkActions(library: library, target: .song(id: song.id), isStarred: song.isStarred, userRating: song.userRating)
                            }
                            AirPlayButton()
                                .frame(width: 32, height: 32)
                            if !song.isLive {
                                Button("Lyrics", systemImage: "quote.bubble") { isLyricsOpen = true }
                                Button("Visualizer", systemImage: "waveform") { isVisualizerOpen = true }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        // Borderless, like the transport controls. With the default style a
                        // button in a list row is drawn in the text color instead of the
                        // accent, and takes taps anywhere in the row.
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        // A station Spin the Dial found, not saved yet.
                        if let status = saveState(song), let savedStations {
                            SaveStationButton(library: library, song: song, stations: savedStations, status: status) {
                                savedSongID = song.id
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                .themedRows()
                Section {
                    QueueList(engine: engine)
                } header: {
                    HStack {
                        if let spinOff = engine.spinOff {
                            Label(spinOff.heading, systemImage: spinOff == .rated ? "flame" : "opticaldisc")
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
                    SleepTimerMenu(timer: library.sleepTimer, isLive: engine.isLive)
                }
                // Nothing in it applies to a radio station.
                if !engine.isLive {
                    ToolbarItem(placement: .primaryAction) {
                        moreMenu
                    }
                }
            }
            // Looks for the station's announced song in the library as it changes.
            .task(id: "\(engine.queue.current?.song.id ?? "")|\(engine.streamTitle ?? "")") {
                let current = engine.queue.current?.song
                await library.onAir.update(
                    announced: current?.isLive == true ? engine.streamTitle : nil,
                    stationName: current?.title
                )
            }
            .libraryDestinations(library)
            .task(id: engine.queue.current?.song.id) {
                // Here, on the screen, which always exists: a task on the button
                // itself wouldn't run while it shows nothing.
                guard let song = engine.queue.current?.song, SpinTheDialModel.isDialed(song) else { return }
                let stations = savedStations ?? library.radioStationsModel()
                savedStations = stations
                await stations.load()
            }
            .addToPlaylistSheet(library)
            .infoSheet(library)
            // The app's messages here while Now Playing is on top (not
            // while the visualizer or Lyrics covers it: they show them).
            .appMessages(library, isEnabled: !isVisualizerOpen && !isLyricsOpen)
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

/// Under a station's controls when the song it's playing is in the library:
/// play your copy instead, or open its album.
private struct InYourLibraryBadge: View {
    let library: Library
    let song: Song

    var body: some View {
        Menu {
            Button("Play It Now", systemImage: "play.fill") {
                library.engine.play(songs: [song])
            }
            if let albumID = song.albumID {
                NavigationLink(value: LibraryRoute.album(id: albumID)) {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
        } label: {
            Label("In Your Library", systemImage: "music.note.house")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.tint.opacity(0.15), in: .capsule)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHint("\(song.title) by \(song.artist ?? "an unknown artist") is in your library")
    }
}
