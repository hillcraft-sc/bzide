import NavidromeCore
import SwiftUI

/// Search as you type, with a scope (All, Artists, Albums, Songs) and filters
/// (rating, favorites, downloaded). With nothing typed and no filter, the
/// genre grid; with a filter on, everything in the library that matches.
/// The scope and filters are remembered until cleared.
struct SearchView: View {
    let library: Library
    /// Bumped to put the cursor in the search field (the Search quick action).
    var focusRequest = 0
    @State private var model: SearchModel
    @FocusState private var isSearchFocused: Bool
    /// The scope and filters, saved on this device.
    @AppStorage("searchFilters") private var savedFilters = Data()

    init(library: Library, focusRequest: Int = 0) {
        self.library = library
        self.focusRequest = focusRequest
        _model = State(initialValue: library.searchModel())
    }

    var body: some View {
        Group {
            // Nothing typed and no filter: browse by genre instead of an empty screen.
            if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !model.filters.isFiltering {
                GenreGrid(library: library)
            } else {
                results
            }
        }
        .safeAreaInset(edge: .top) { filterSummary }
        .navigationTitle("Search")
        .searchable(text: Binding(get: { model.query }, set: { model.updateQuery($0) }), prompt: "Artists, albums, songs")
        .searchFocused($isSearchFocused)
        .onChange(of: focusRequest, initial: true) { _, request in
            if request > 0 { isSearchFocused = true }
        }
        .searchScopes(Binding(get: { model.filters.scope }, set: { model.filters.scope = $0 }), activation: .onSearchPresentation) {
            ForEach(SearchFilters.Scope.allCases, id: \.self) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .toolbar {
            ToolbarItem {
                filterMenu
            }
        }
        .onAppear {
            if let saved = try? JSONDecoder().decode(SearchFilters.self, from: savedFilters) {
                model.filters = saved
            }
        }
        .onChange(of: model.filters) { _, filters in
            savedFilters = (try? JSONEncoder().encode(filters)) ?? Data()
        }
    }

    /// Rating, favorites and downloaded filters, and Clear. The funnel fills in
    /// while any is on.
    private var filterMenu: some View {
        Menu {
            Picker("Rating", selection: Binding(get: { model.filters.rating }, set: { model.filters.rating = $0 })) {
                ForEach(SearchFilters.RatingFilter.allCases, id: \.self) { rating in
                    Text(rating.title).tag(rating)
                }
            }
            .pickerStyle(.inline)
            Section {
                Toggle("Favorites Only", systemImage: "heart", isOn: Binding(get: { model.filters.favoritesOnly }, set: { model.filters.favoritesOnly = $0 }))
                Toggle("Downloaded Only", systemImage: "arrow.down.circle", isOn: Binding(get: { model.filters.downloadedOnly }, set: { model.filters.downloadedOnly = $0 }))
            }
            if model.filters.isFiltering || model.filters.scope != .all {
                Section {
                    Button("Clear Filters", systemImage: "xmark.circle") { model.filters = SearchFilters() }
                }
            }
        } label: {
            Label("Filters", systemImage: model.filters.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityValue(model.filters.summary ?? "None")
    }

    /// What's narrowing the results, e.g. "Albums · Love · Favorites", with Clear.
    @ViewBuilder
    private var filterSummary: some View {
        let parts = [model.filters.scope == .all ? nil : model.filters.scope.title, model.filters.summary].compactMap { $0 }
        if !parts.isEmpty {
            HStack {
                Label(parts.joined(separator: " · "), systemImage: "line.3.horizontal.decrease")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Button("Clear") { model.filters = SearchFilters() }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var results: some View {
        List {
            Group {
                if let results = model.visibleResults {
                    if !results.artists.isEmpty {
                        Section("Artists") {
                            ForEach(results.artists) { artist in
                                NavigationLink(artist.name.isEmpty ? "Unknown Artist" : artist.name, value: LibraryRoute.artist(id: artist.id))
                                    .contextMenu { ArtistRowMenu(library: library, artist: artist) }
                                    .siriEntity(artistID: artist.id)
                            }
                        }
                    }
                    if !results.albums.isEmpty {
                        Section("Albums") {
                            ForEach(results.albums) { album in
                                NavigationLink(value: LibraryRoute.album(id: album.id)) {
                                    AlbumRow(library: library, album: album)
                                }
                                .contextMenu { AlbumRowMenu(library: library, album: album) }
                                .siriEntity(albumID: album.id)
                            }
                        }
                    }
                    if !results.songs.isEmpty {
                        Section("Songs") {
                            ForEach(Array(results.songs.enumerated()), id: \.offset) { index, song in
                                Button {
                                    library.engine.play(songs: results.songs, startIndex: index)
                                } label: {
                                    SongRow(
                                        song: song, isCurrent: song.id == library.engine.queue.current?.song.id,
                                        isFavorite: library.isFavorite(song), rating: library.rating(of: song)
                                    )
                                }
                                .foregroundStyle(.primary)
                                .contextMenu { SongActions(library: library, song: song) }
                                .siriEntity(songID: song.id)
                            }
                        }
                    }
                }
            }
            .themedRows()
        }
        .listStyle(.plain)
        .themedList()
        .overlay { overlay }
    }

    @ViewBuilder private var overlay: some View {
        if let error = model.error {
            ContentUnavailableView {
                Label("Search Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { model.retry() }
            }
        } else if model.isSearching, model.results == nil {
            ProgressView()
        } else if let results = model.visibleResults, results.artists.isEmpty, results.albums.isEmpty, results.songs.isEmpty {
            if model.isBrowsing {
                ContentUnavailableView(
                    "Nothing Matches",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(browseEmptyHint)
                )
            } else if model.filters.isFiltering || model.filters.scope != .all {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Nothing for \u{201C}\(model.query)\u{201D} matches these filters.")
                )
            } else {
                ContentUnavailableView.search(text: model.query)
            }
        }
    }

    /// Why browsing found nothing. Songs can only be browsed on servers that
    /// list all their songs (Navidrome does).
    private var browseEmptyHint: String {
        let base = "Nothing in your library matches these filters."
        guard model.filters.scope == .all || model.filters.scope == .songs else { return base }
        return base + " Songs can only be browsed on servers that can list all their songs."
    }
}
