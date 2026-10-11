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
        .alert("Couldn't Change Star", isPresented: starErrorShown) {
            Button("OK") { library.stars.dismissError() }
        } message: {
            Text(library.stars.error ?? "")
        }
    }

    private var starErrorShown: Binding<Bool> {
        Binding(get: { library.stars.error != nil }, set: { if !$0 { library.stars.dismissError() } })
    }
}
