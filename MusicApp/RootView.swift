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
        .alert("Couldn't Load Album", isPresented: albumQueueErrorShown) {
            Button("OK") { library.albumQueue.dismissError() }
        } message: {
            Text(library.albumQueue.error ?? "")
        }
    }

    private var favoriteErrorShown: Binding<Bool> {
        Binding(get: { library.stars.error != nil }, set: { if !$0 { library.stars.dismissError() } })
    }

    private var albumQueueErrorShown: Binding<Bool> {
        Binding(get: { library.albumQueue.error != nil }, set: { if !$0 { library.albumQueue.dismissError() } })
    }

    private var ratingErrorShown: Binding<Bool> {
        Binding(get: { library.ratings.error != nil }, set: { if !$0 { library.ratings.dismissError() } })
    }
}
