import NavidromeCore
import SwiftUI

/// Everything favorited (hearted), from the server: songs first, with Play
/// and Shuffle, then albums and artists. Unfavoriting something anywhere takes
/// it off the list at once; it reloads each time it's opened. A bar picks one
/// kind, the search field narrows by name, and the funnel filters by rating
/// or downloads and sets the order (see `FavoritesFilters`).
struct FavoritesView: View {
    let library: Library
    @State private var model: LoadModel<SearchResult>
    @State private var filters = FavoritesFilters()
    @State private var text = ""
    /// The scope, filters and order, saved on this device.
    @AppStorage("favoritesFilters") private var savedFilters = Data()
    @Environment(\.simplifiedRating) private var simplifiedRating

    init(library: Library) {
        self.library = library
        _model = State(initialValue: library.favoritesModel())
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { favorites in
            let starred = SearchResult(
                artists: favorites.artists.filter { library.stars.isStarred(.artist(id: $0.id), fromServer: true) },
                albums: favorites.albums.filter { library.stars.isStarred(.album(id: $0.id), fromServer: true) },
                songs: favorites.songs.filter { library.stars.isStarred(.song(id: $0.id), fromServer: true) }
            )
            let shown = filters.apply(to: starred, text: text, isSongDownloaded: library.isSongDownloaded, isAlbumDownloaded: library.isAlbumDownloaded)
            let (songs, albums, artists) = (shown.songs, shown.albums, shown.artists)
            FilterBarStack(showsBar: !starred.isEmpty) {
                scopeBar
            } content: {
            List {
                if !songs.isEmpty {
                    Section {
                        HStack(spacing: 12) {
                            Button("Play", systemImage: "play.fill") { library.engine.play(songs: songs) }
                            Button("Shuffle", systemImage: "shuffle") { library.engine.playShuffled(songs) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            Button {
                                library.engine.play(songs: songs, startIndex: index)
                            } label: {
                                SongRow(
                                    song: song,
                                    isCurrent: song.id == library.engine.queue.current?.song.id,
                                    showsTrackNumber: false,
                                    isFavorite: library.isFavorite(song),
                                    stars: library.stars(of: song)
                                )
                            }
                            .foregroundStyle(.primary)
                            .contextMenu { SongActions(library: library, song: song, showsGoToAlbum: true) }
                            .siriEntity(songID: song.id)
                        }
                    } header: {
                        Text("Songs")
                    }
                    .themedRows()
                }
                if !albums.isEmpty {
                    Section("Albums") {
                        ForEach(albums) { album in
                            NavigationLink(value: LibraryRoute.album(id: album.id)) {
                                AlbumRow(library: library, album: album)
                            }
                            .contextMenu { AlbumRowMenu(library: library, album: album) }
                            .siriEntity(albumID: album.id)
                        }
                    }
                    .themedRows()
                }
                if !artists.isEmpty {
                    Section("Artists") {
                        ForEach(artists) { artist in
                            NavigationLink(value: LibraryRoute.artist(id: artist.id)) {
                                Text(artist.name.isEmpty ? "Unknown Artist" : artist.name)
                            }
                            .contextMenu { ArtistRowMenu(library: library, artist: artist) }
                            .siriEntity(artistID: artist.id)
                        }
                    }
                    .themedRows()
                }
            }
            .listStyle(.plain)
            .themedList()
            .overlay {
                if starred.isEmpty {
                    ContentUnavailableView(
                        "No Favorites",
                        systemImage: "heart",
                        description: Text("Tap the heart on a song, album or artist to add it here.")
                    )
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: text.isEmpty ? "" : text)
                }
            }
            }
        }
        .navigationTitle("Favorites")
        .searchable(text: $text, prompt: "Favorites")
        .toolbar {
            ToolbarItem { filterMenu }
        }
        .onAppear {
            if let saved = try? JSONDecoder().decode(FavoritesFilters.self, from: savedFilters) { filters = saved }
            filters.rating = filters.rating.inStyle(simplified: simplifiedRating)
        }
        // A rating filter from the other style would hide favorites unseen.
        .onChange(of: simplifiedRating) {
            filters.rating = filters.rating.inStyle(simplified: simplifiedRating)
        }
        .onChange(of: filters) { _, filters in
            savedFilters = (try? JSONEncoder().encode(filters)) ?? Data()
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    /// All, Songs, Albums or Artists, plus what the funnel is filtering, with Clear.
    private var scopeBar: some View {
        VStack(spacing: 8) {
            Picker("Show", selection: $filters.scope) {
                ForEach([SearchFilters.Scope.all, .songs, .albums, .artists], id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if let summary = filters.summary {
                HStack {
                    Label(summary, systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Button("Clear") { filters.clear() }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Rating, Downloaded Only and the order. The funnel fills in while a filter is on.
    private var filterMenu: some View {
        Menu {
            Picker("Sort By", selection: $filters.sort) {
                ForEach(FavoritesFilters.Sort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Rating", selection: $filters.rating) {
                ForEach(SearchFilters.RatingFilter.choices(simplified: simplifiedRating), id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Section {
                Toggle("Downloaded Only", systemImage: "arrow.down.circle", isOn: $filters.downloadedOnly)
            }
            if filters.isFiltering {
                Section {
                    Button("Clear Filters", systemImage: "xmark.circle") { filters.clear() }
                }
            }
        } label: {
            Label("Filters", systemImage: filters.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityValue(filters.summary ?? "None")
    }
}
