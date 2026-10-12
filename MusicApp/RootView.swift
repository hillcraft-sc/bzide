import NavidromeCore
import SwiftUI

/// Signed in: Library and Search tabs, with the mini player above the tab bar.
struct RootView: View {
    let model: AppModel
    let library: Library
    @State private var isNowPlayingOpen = false

    var body: some View {
        TabView {
            Tab("Library", systemImage: "music.note.house") {
                NavigationStack {
                    LibraryView(model: model, library: library)
                        .libraryDestinations(library)
                }
            }
            Tab(role: .search) {
                NavigationStack {
                    SearchView(library: library)
                        .libraryDestinations(library)
                }
            }
        }
        .tabViewBottomAccessory {
            MiniPlayer(library: library) { isNowPlayingOpen = true }
        }
        .sheet(isPresented: $isNowPlayingOpen) {
            NowPlayingView(library: library)
        }
        .addToPlaylistSheet(library, isEnabled: !isNowPlayingOpen)
        .playlistConfirmation(library.playlistEditor)
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
