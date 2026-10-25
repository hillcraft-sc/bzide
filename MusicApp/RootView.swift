import NavidromeCore
import SwiftUI

/// Signed in: Library and Search tabs, with the mini player above the tab bar.
struct RootView: View {
    let model: AppModel
    let library: Library
    @State private var isNowPlayingOpen = false
    @State private var tab = RootTab.library
    @State private var searchFocusRequest = 0
    @State private var libraryPath = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase

    private enum RootTab: Hashable {
        case library, search
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Library", systemImage: "music.note.house", value: RootTab.library) {
                NavigationStack(path: $libraryPath) {
                    LibraryView(model: model, library: library)
                        .libraryDestinations(library)
                }
                .queueOffer(library.queueSync)
            }
            Tab(value: RootTab.search, role: .search) {
                NavigationStack {
                    SearchView(library: library, focusRequest: searchFocusRequest)
                        .libraryDestinations(library)
                }
                .queueOffer(library.queueSync)
            }
        }
        // iPad: tabs that open into a sidebar (Gitea #22); iPhone keeps its tab bar.
        .tabViewStyle(.sidebarAdaptable)
        .tabViewBottomAccessory {
            MiniPlayer(library: library) { isNowPlayingOpen = true }
        }
        .nowPlaying(isPresented: $isNowPlayingOpen) {
            NowPlayingView(model: model, library: library)
        }
        .addToPlaylistSheet(library, isEnabled: !isNowPlayingOpen)
        .playlistPrompts(library, isEnabled: !isNowPlayingOpen)
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
            if phase == .background { saveQueueToServer() }
            guard phase == .active else { return }
            Task { await library.playlistRefresher.refreshAllIfDue() }
            // A queue saved since on another device or app is offered.
            Task { await library.queueSync?.checkServer() }
        }
        .onChange(of: library.settings.settings.syncQueueWithServer) { _, isOn in
            if !isOn { library.queueSync?.turnedOff() }
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
        #if DEBUG
        .task { await runScreenshotScript() }
        #endif
        .onDisappear { HomeScreenActions.clear() }
        // Messages from anywhere in the app, shown here unless Now Playing is open.
        .appMessages(library, isEnabled: !isNowPlayingOpen)
        // Meh, Like and Love, or stars, everywhere a rating shows or is chosen.
        .environment(\.simplifiedRating, library.settings.settings.useSimplifiedRating)
    }

    /// With the position, before the app is suspended: the system allows a
    /// few seconds for it. If they run out first, the task is ended there
    /// (iOS ends an app that leaves one running); the save is tried again
    /// next time.
    private func saveQueueToServer() {
        guard let sync = library.queueSync else { return }
        let task = BackgroundTask(name: "Save Queue")
        Task {
            await sync.saveNow()
            task.end()
        }
    }

    #if DEBUG
    private func runScreenshotScript() async {
        guard let screen = ScreenshotScript.screen,
              let album = await ScreenshotScript.playAlbum(library)
        else { return }
        switch screen {
        case .library: break
        case .albums: libraryPath.append(LibraryRoute.albums)
        case .album: libraryPath.append(LibraryRoute.album(id: album.id))
        case .artist:
            if let artistID = album.artistID { libraryPath.append(LibraryRoute.artist(id: artistID)) }
        case .nowPlaying, .visualizer, .lyrics: isNowPlayingOpen = true
        }
    }
    #endif

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

extension View {
    /// Now Playing: a sheet in a compact window (every iPhone: swipe down to
    /// close), full screen in a window regular both ways (iPad, Gitea #22),
    /// where a sheet would be a card in the middle; there it closes with its
    /// chevron. By the space, not the device, as all layouts here. Full screen
    /// and wider than tall, it shows the queue beside the controls.
    func nowPlaying(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> some View) -> some View {
        modifier(NowPlayingPresentation(isPresented: isPresented, screen: content))
    }
}

private struct NowPlayingPresentation<Screen: View>: ViewModifier {
    @Binding var isPresented: Bool
    let screen: () -> Screen
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.verticalSizeClass) private var vertical

    func body(content: Content) -> some View {
        if horizontal == .regular && vertical == .regular {
            content.fullScreenCover(isPresented: $isPresented, content: screen)
        } else {
            content.sheet(isPresented: $isPresented, content: screen)
        }
    }
}
