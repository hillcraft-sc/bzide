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
        // The Now Playing widget opens Now Playing (bzide://now-playing).
        .onOpenURL { url in
            if url == WidgetLinks.nowPlaying { isNowPlayingOpen = library.engine.queue.current != nil }
        }
        .onAppear { HomeScreenActions.update(current: library.engine.queue.current?.song) }
        .onDisappear { HomeScreenActions.clear() }
        // Messages from anywhere in the app, shown here unless Now Playing is open.
        .appMessages(library, isEnabled: !isNowPlayingOpen)
        // Meh, Like and Love, or stars, everywhere a rating shows or is chosen.
        .environment(\.simplifiedRating, library.settings.settings.useSimplifiedRating)
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
}
