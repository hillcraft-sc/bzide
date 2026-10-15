import NavidromeCore
import SwiftUI

/// Signed in: Library and Search tabs, with the mini player above the tab bar.
struct RootView: View {
    let model: AppModel
    let library: Library
    @State private var isNowPlayingOpen = false
    @State private var tab = RootTab.library
    @State private var searchFocusRequest = 0
    @Environment(\.scenePhase) private var scenePhase

    private enum RootTab: Hashable {
        case library, search
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Library", systemImage: "music.note.house", value: RootTab.library) {
                NavigationStack {
                    LibraryView(model: model, library: library)
                        .libraryDestinations(library)
                }
            }
            Tab(value: RootTab.search, role: .search) {
                NavigationStack {
                    SearchView(library: library, focusRequest: searchFocusRequest)
                        .libraryDestinations(library)
                }
            }
        }
        .tabViewBottomAccessory {
            MiniPlayer(library: library) { isNowPlayingOpen = true }
        }
        .sheet(isPresented: $isNowPlayingOpen) {
            NowPlayingView(model: model, library: library)
        }
        .addToPlaylistSheet(library, isEnabled: !isNowPlayingOpen)
        .infoSheet(library, isEnabled: !isNowPlayingOpen)
        // Each return to the app checks downloaded playlists for changes (at
        // most every 15 minutes; see PlaylistDownloadRefresher).
        // A new normalization setting applies to the songs already lined up too.
        .onChange(of: library.settings.settings.volumeNormalization) {
            library.engine.refreshGains()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // The icon's quick actions follow the queue (Continue names it).
            if phase != .active { HomeScreenActions.update(current: library.engine.queue.current?.song) }
            guard phase == .active else { return }
            Task { await library.playlistRefresher.refreshAllIfDue() }
        }
        .onChange(of: model.pendingHomeScreenAction, initial: true) { _, action in
            guard let action else { return }
            model.pendingHomeScreenAction = nil
            run(action)
        }
        .onAppear { HomeScreenActions.update(current: library.engine.queue.current?.song) }
        .onDisappear { HomeScreenActions.clear() }
        .playlistConfirmation(library.playlistEditor)
        .noticeBanner(library.spinOff.notice, seconds: 5) { library.spinOff.dismissNotice() }
        .alert("Couldn't Change Favorite", isPresented: favoriteErrorShown) {
            Button("OK") { library.stars.dismissError() }
        } message: {
            Text(library.stars.error ?? "")
        }
        .alert("Couldn't Change Rating", isPresented: ratingErrorShown) {
            Button("OK") { library.ratings.dismissError() }
        } message: {
            Text(library.ratings.error ?? "")
        }
        .alert("Couldn't Play Station", isPresented: radioErrorShown) {
            Button("OK") { library.radio.dismissError() }
        } message: {
            Text(library.radio.error ?? "")
        }
        .alert("Couldn't Load Songs", isPresented: quickActionsErrorShown) {
            Button("OK") { library.quickActions.dismissError() }
        } message: {
            Text(library.quickActions.error ?? "")
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationShown,
            titleVisibility: .visible,
            presenting: library.quickActions.confirmation
        ) { confirmation in
            Button(Self.confirmButton(confirmation.action)) {
                Task { await library.quickActions.confirm() }
            }
            Button("Cancel", role: .cancel) { library.quickActions.cancelConfirmation() }
        }
    }

    private func run(_ action: HomeScreenAction) {
        switch action {
        case .resume:
            tab = .library
            library.engine.play()
        case .randomMix:
            tab = .library
            Task { await library.randomMix.start() }
        case .myCuts:
            tab = .library
            Task { await library.spinOff.startRated() }
        case .search:
            isNowPlayingOpen = false
            tab = .search
            searchFocusRequest += 1
        }
    }

    private var favoriteErrorShown: Binding<Bool> {
        Binding(get: { library.stars.error != nil }, set: { if !$0 { library.stars.dismissError() } })
    }

    private var radioErrorShown: Binding<Bool> {
        Binding(get: { library.radio.error != nil }, set: { if !$0 { library.radio.dismissError() } })
    }

    private var quickActionsErrorShown: Binding<Bool> {
        Binding(get: { library.quickActions.error != nil }, set: { if !$0 { library.quickActions.dismissError() } })
    }

    private var confirmationShown: Binding<Bool> {
        Binding(
            get: { library.quickActions.confirmation != nil },
            set: { if !$0 { library.quickActions.cancelConfirmation() } }
        )
    }

    /// "Add 340 songs by Artist to the queue?"
    private var confirmationTitle: String {
        guard let confirmation = library.quickActions.confirmation else { return "" }
        let songs = "\(confirmation.songCount) songs by \(confirmation.artist.name)"
        return switch confirmation.action {
        case .play: "Play \(songs)?"
        case .shuffle: "Shuffle \(songs)?"
        case .playNext: "Play \(songs) next?"
        case .addToQueue: "Add \(songs) to the queue?"
        case .addToPlaylist: "Add \(songs) to a playlist?"
        case .download: "Download \(songs)?"
        }
    }

    private static func confirmButton(_ action: QuickActions.Action) -> String {
        switch action {
        case .play: "Play"
        case .shuffle: "Shuffle"
        case .playNext: "Play Next"
        case .addToQueue: "Add to Queue"
        case .addToPlaylist: "Choose Playlist"
        case .download: "Download"
        }
    }

    private var ratingErrorShown: Binding<Bool> {
        Binding(get: { library.ratings.error != nil }, set: { if !$0 { library.ratings.dismissError() } })
    }
}
