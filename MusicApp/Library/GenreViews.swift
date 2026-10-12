import NavidromeCore
import SwiftUI

/// The library's genres as coloured tiles, biggest first, shown on Search
/// before anything is typed. Tapping one opens its page; long-press plays it.
struct GenreGrid: View {
    let library: Library
    @State private var model: LoadModel<[Genre]>
    @Environment(\.catppuccin) private var palette

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(library: Library) {
        self.library = library
        _model = State(initialValue: library.genresModel())
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { genres in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(genres) { genre in
                        NavigationLink(value: LibraryRoute.genre(genre.name)) {
                            GenreTile(library: library, genre: genre)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { QuickActionButtons(library: library, source: .genre(genre.name)) }
                    }
                }
                .padding(16)
            }
            .background(palette.map { Color($0.base) } ?? .clear)
            .overlay {
                if genres.isEmpty {
                    ContentUnavailableView(
                        "No Genres",
                        systemImage: "guitars",
                        description: Text("Search for artists, albums and songs above.")
                    )
                }
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

/// A colour block with the genre's name and one of its covers tilted in the corner.
private struct GenreTile: View {
    let library: Library
    let genre: Genre
    @Environment(\.catppuccin) private var palette

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(GenreColors.color(for: genre.name, palette: palette))
            ArtworkView(library: library, coverArtID: library.genreCovers.coverArtID(for: genre.name), side: 72)
                .shadow(radius: 4, y: 2)
                .rotationEffect(.degrees(18))
                .offset(x: 14, y: -6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            Text(genre.name)
                .font(.headline)
                .foregroundStyle(GenreColors.textColor(palette: palette))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(12)
        }
        .frame(height: 104)
        .clipShape(.rect(cornerRadius: 14))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(genre.name)
        .accessibilityValue(genre.albumCount.map { $0 == 1 ? "1 album" : "\($0) albums" } ?? "")
        .accessibilityAddTraits(.isButton)
        .task { await library.genreCovers.load(genre.name) }
    }
}

/// Tile colours: the Catppuccin accents in a Catppuccin theme, otherwise
/// system colours. Each genre keeps its colour from launch to launch.
private enum GenreColors {
    private static let system: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .red, .green, .cyan, .mint, .brown]

    static func color(for name: String, palette: CatppuccinPalette?) -> Color {
        // A stable sum, not `hashValue`, which changes every launch.
        let index = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        if let palette {
            let accents = CatppuccinAccent.allCases
            return Color(palette.accent(accents[index % accents.count]))
        }
        return system[index % system.count]
    }

    /// Catppuccin's dark flavours have pastel accents, which need dark text.
    static func textColor(palette: CatppuccinPalette?) -> Color {
        guard let palette, palette != .latte else { return .white }
        return Color(palette.crust)
    }
}

/// A genre's page: play or shuffle it, then its albums, paged as you scroll.
struct GenreView: View {
    let library: Library
    let genre: String
    @State private var model: AlbumsModel

    init(library: Library, genre: String) {
        self.library = library
        self.genre = genre
        _model = State(initialValue: library.genreAlbumsModel(genre))
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { albums in
            List {
                Section {
                    HStack(spacing: 12) {
                        Button("Play", systemImage: "play.fill") { run(.play) }
                        Button("Shuffle", systemImage: "shuffle") { run(.shuffle) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                }
                .themedRows()
                Section {
                    ForEach(albums) { album in
                        NavigationLink(value: LibraryRoute.album(id: album.id)) {
                            AlbumRow(library: library, album: album)
                        }
                        .contextMenu { AlbumRowMenu(library: library, album: album) }
                        .siriEntity(albumID: album.id)
                        .task { await model.loadMoreIfNeeded(after: album) }
                    }
                }
                .themedRows()
                Group {
                    if model.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let error = model.loadMoreError {
                        VStack(spacing: 8) {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            Button("Load More") { Task { await model.loadMore() } }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .themedRows()
            }
            .listStyle(.plain)
            .themedList()
            .overlay {
                if albums.isEmpty {
                    ContentUnavailableView("No Albums", systemImage: "square.stack")
                }
            }
        }
        .navigationTitle(genre)
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func run(_ action: QuickActions.Action) {
        Task { await library.quickActions.perform(action, on: .genre(genre)) }
    }
}
