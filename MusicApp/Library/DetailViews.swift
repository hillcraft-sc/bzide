import NavidromeCore
import SwiftUI

/// Where a library link goes. Each tab's navigation stack resolves these with
/// `libraryDestinations(_:)`.
enum LibraryRoute: Hashable {
    case artists
    case albums
    case playlists
    case downloads
    case history
    case wishlist
    case radio
    case favorites
    case genres
    case genre(String)
    case artist(id: String)
    case album(id: String)
    case playlist(id: String)
}

extension View {
    func libraryDestinations(_ library: Library) -> some View {
        navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case .artists: ArtistsView(library: library)
            case .albums: AlbumsView(library: library)
            case .playlists: PlaylistsView(library: library)
            case .downloads: DownloadsView(library: library)
            case .history: HistoryView(library: library)
            case .wishlist: WishlistView(library: library)
            case .radio: RadioView(library: library)
            case .favorites: FavoritesView(library: library)
            case .genres: GenreGrid(library: library).navigationTitle("Genres")
            case .genre(let name): GenreView(library: library, genre: name)
            case .artist(let id): ArtistView(library: library, id: id)
            case .album(let id): AlbumView(library: library, id: id)
            case .playlist(let id): PlaylistView(library: library, id: id)
            }
        }
    }
}

struct AlbumView: View {
    let library: Library
    @State private var model: LoadModel<Album>

    init(library: Library, id: String) {
        self.library = library
        _model = State(initialValue: library.albumModel(id: id))
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { album in
            SongListView(library: library, songs: album.songs, showsTrackNumbers: true) {
                SongListHeader(
                    library: library,
                    coverArtID: album.coverArtID,
                    title: album.name,
                    subtitle: [album.artist, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · "),
                    detail: MediaInfo.albumDetailsLine(album),
                    note: marksIncomplete ? library.albumCompleteness.completeness(of: album.id)?.detail : nil,
                    noteLink: MusicBrainzClient.albumPage(album)
                )
                .siriEntity(albumID: album.id)
            }
            .toolbar {
                ToolbarItem {
                    DownloadButton(downloads: library.downloads, collection: DownloadCollection(album: album))
                }
                ToolbarItem {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Play Next", systemImage: "text.insert") { library.engine.playNext(album.songs) }
                        Button("Add to Queue", systemImage: "text.append") { library.engine.append(album.songs) }
                        AddToPlaylistButton(library: library, songs: album.songs)
                        MarkActions(library: library, target: .album(id: album.id), isStarred: album.isStarred, userRating: album.userRating)
                        AlbumInfoButton(library: library, albumID: album.id)
                        if canAddMissingSongs(album) {
                            Button("Add Missing Songs to Wishlist", systemImage: "tag") {
                                Task { await addMissingSongs(album) }
                            }
                        }
                        if let artistID = album.artistID {
                            NavigationLink(value: LibraryRoute.artist(id: artistID)) {
                                Label("Go to Artist", systemImage: "music.microphone")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(model.value?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var marksIncomplete: Bool { library.settings.settings.markIncompleteAlbums }

    /// Only when MusicBrainz can say which songs (Look Up Artists Online) and
    /// the album is known to be missing some.
    private func canAddMissingSongs(_ album: Album) -> Bool {
        marksIncomplete && library.settings.settings.lookUpArtistsOnline
            && library.albumCompleteness.completeness(of: album.id)?.isIncomplete == true
    }

    /// The release's songs you don't have, by title, onto the Wishlist.
    private func addMissingSongs(_ album: Album) async {
        guard let missing = await library.albumCompleteness.missingSongs(of: album) else {
            library.wishlist.explain("Couldn't get this album's songs from MusicBrainz.")
            return
        }
        library.wishlist.addMissingSongs(
            missing.titles, album: album.name, artist: album.artist ?? "", year: album.year,
            coverURL: MusicBrainzClient.coverArtURL.appending(path: "release/\(missing.release.id)/front-250"),
            musicBrainzURL: URL(string: "https://musicbrainz.org/release/\(missing.release.id)")
        )
    }

    /// The album, then whether it's missing tracks (after, so it never holds it up).
    private func load() async {
        await model.load()
        if marksIncomplete, let album = model.value {
            await library.albumCompleteness.load(album, online: library.settings.settings.lookUpArtistsOnline)
        }
    }
}

struct PlaylistView: View {
    let library: Library
    let id: String
    @State private var model: LoadModel<Playlist>
    @State private var songEditor: PlaylistSongEditor
    @Environment(\.dismiss) private var dismiss

    init(library: Library, id: String) {
        self.library = library
        self.id = id
        _model = State(initialValue: library.playlistModel(id: id))
        _songEditor = State(initialValue: library.playlistSongEditor(id: id))
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { playlist in
            let songs = songEditor.shown(playlist.songs)
            SongListView(
                library: library, songs: songs, showsTrackNumbers: false,
                editing: library.playlistEditor.isOwned(playlist) ? editing(songs) : nil
            ) {
                SongListHeader(
                    library: library,
                    coverArtID: playlist.coverArtID,
                    title: playlist.name,
                    subtitle: playlist.songCount.map { "\($0) songs" }
                )
                .siriEntity(playlistID: playlist.id)
            }
            .toolbar {
                ToolbarItem {
                    DownloadButton(downloads: library.downloads, collection: DownloadCollection(playlist: playlist))
                }
                ToolbarItem {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Play Next", systemImage: "text.insert") { library.engine.playNext(playlist.songs) }
                        Button("Add to Queue", systemImage: "text.append") { library.engine.append(playlist.songs) }
                        AddToPlaylistButton(library: library, songs: playlist.songs)
                        PlaylistManageButtons(library: library, playlist: playlist)
                    }
                }
            }
        }
        .navigationTitle(model.value?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        // Renamed or shared from the menu: show it.
        .onChange(of: library.playlistEditor.revision) {
            Task { await model.load() }
        }
        // Deleted: there's nothing left to show.
        .onChange(of: library.playlistEditor.deletedIDs.contains(id)) { _, deleted in
            if deleted { dismiss() }
        }
        .alert("Couldn't Change Playlist", isPresented: Binding(
            get: { songEditor.error != nil },
            set: { if !$0 { songEditor.dismissError() } }
        )) {
            Button("OK") { songEditor.dismissError() }
        } message: {
            Text(songEditor.error ?? "")
        }
    }

    /// Removing and moving songs, saved to the server, then the page reloads.
    private func editing(_ songs: [Song]) -> SongListEditing {
        SongListEditing(
            remove: { offsets in
                Task { await songEditor.remove(atOffsets: offsets, from: songs, reload: reload) }
            },
            move: { offsets, destination in
                Task { await songEditor.move(fromOffsets: offsets, toOffset: destination, in: songs, reload: reload) }
            }
        )
    }

    private func reload() async {
        await model.load()
        library.playlistEditor.noteChange()
    }
}

struct ArtistView: View {
    let library: Library
    @State private var model: LoadModel<Artist>
    /// Loaded separately: a slow or failed lookup never holds up the albums.
    @State private var info: LoadModel<ArtistInfo>
    /// Look Up Artists Online's extras, after the rest.
    @State private var online: OnlineArtistModel

    init(library: Library, id: String) {
        self.library = library
        _model = State(initialValue: library.artistModel(id: id))
        _info = State(initialValue: library.artistInfoModel(id: id))
        _online = State(initialValue: library.onlineArtistModel())
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { artist in
            List {
                Section {
                    ArtistHeader(
                        library: library, artist: artist,
                        biography: online.biography.map { Biography.Content(text: $0.text, credit: $0) }
                            ?? info.value?.biography.map { Biography.Content(text: $0) }
                    )
                        .siriEntity(artistID: artist.id)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
                .themedRows()
                Section {
                    ForEach(artist.albums) { album in
                        NavigationLink(value: LibraryRoute.album(id: album.id)) {
                            AlbumRow(library: library, album: album, badge: marksIncomplete ? library.albumCompleteness.completeness(of: album.id)?.badge : nil)
                        }
                        .contextMenu { AlbumRowMenu(library: library, album: album, showsGoToArtist: false) }
                        .siriEntity(albumID: album.id)
                    }
                    if artist.albums.isEmpty {
                        Text("No Albums").foregroundStyle(.secondary)
                    }
                } header: {
                    if online.discography != .off { Text("In Your Library") }
                }
                .themedRows()
                NotOwnedSections(library: library, artistName: artist.name, state: online.discography) {
                    Task { await online.load(artist, info: info.value, enabled: library.settings.settings.lookUpArtistsOnline) }
                }
                SimilarArtistsSection(library: library, artists: info.value?.similarArtists ?? [])
            }
            .listStyle(.plain)
            .themedList()
            .toolbar {
                ToolbarItem {
                    Menu("More", systemImage: "ellipsis") {
                        ArtistRowMenu(library: library, artist: artist)
                    }
                }
            }
        }
        .navigationTitle(model.value?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var marksIncomplete: Bool { library.settings.settings.markIncompleteAlbums }

    private func load() async {
        async let albums: Void = model.load()
        async let biography: Void = info.load()
        _ = await (albums, biography)
        if let artist = model.value {
            let online = library.settings.settings.lookUpArtistsOnline
            async let extras: Void = self.online.load(artist, info: info.value, enabled: online)
            if marksIncomplete {
                await library.albumCompleteness.load(artist, info: info.value, online: online)
            }
            await extras
        }
    }
}

/// Artist image and name, then the first lines of the biography; tapping
/// More shows the rest.
private struct ArtistHeader: View {
    let library: Library
    let artist: Artist
    let biography: Biography.Content?

    var body: some View {
        VStack(spacing: 8) {
            ArtworkView(library: library, coverArtID: artist.coverArtID, side: 220)
            Text(artist.name.isEmpty ? "Unknown Artist" : artist.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let biography {
                Biography(content: biography)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct Biography: View {
    struct Content {
        var text: String
        /// Set when it's from outside the server, which is credited.
        var credit: ArtistBiography?
    }

    let content: Content
    private var text: String { content.text }

    @State private var isExpanded = false
    @State private var shortHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    /// Only offer More when three lines don't already show it all.
    private var isTruncated: Bool { fullHeight > shortHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .lineLimit(isExpanded ? nil : 3)
                .foregroundStyle(.secondary)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if !isExpanded { shortHeight = $0 } }
                .background(alignment: .top) {
                    // The full text, unseen, to measure against.
                    Text(text)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
            HStack {
                if isTruncated {
                    Button(isExpanded ? "Less" : "More") {
                        withAnimation { isExpanded.toggle() }
                    }
                    .font(.subheadline.bold())
                    .buttonStyle(.borderless)
                }
                Spacer()
                if let credit = content.credit {
                    CreditLink(credit: credit)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "From Wikipedia", linking to the article. Its text is CC BY-SA, which
/// asks for the credit and the link.
private struct CreditLink: View {
    let credit: ArtistBiography

    var body: some View {
        if let url = credit.pageURL {
            Link(destination: url) {
                Label("From \(credit.source)", systemImage: "arrow.up.right")
                    .labelStyle(.titleAndIcon)
            }
            .font(.caption)
            .buttonStyle(.borderless)
        } else {
            Text("From \(credit.source)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The artist's releases the user doesn't have, by kind, from Look Up
/// Artists Online. Each opens its MusicBrainz page. The sections start
/// collapsed, so the page leads with what the user owns.
private struct NotOwnedSections: View {
    let library: Library
    let artistName: String
    let state: OnlineArtistModel.State
    let retry: () -> Void

    @State private var expanded: Set<DiscographyRelease.Kind> = []

    var body: some View {
        switch state {
        case .off:
            EmptyView()
        case .loading:
            Section("Not Owned") {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking up other releases…").foregroundStyle(.secondary)
                }
            }
            .themedRows()
        case .failed:
            Section("Not Owned") {
                Text("Couldn't reach MusicBrainz.").foregroundStyle(.secondary)
                Button("Try Again", action: retry)
            }
            .themedRows()
        case .loaded(let sections):
            ForEach(sections) { section in
                let isExpanded = expanded.contains(section.kind)
                Section {
                    if isExpanded {
                        ForEach(section.releases) { release in
                            NotOwnedRow(library: library, release: release, artistName: artistName)
                        }
                    }
                } header: {
                    Button {
                        withAnimation {
                            if isExpanded { expanded.remove(section.kind) } else { expanded.insert(section.kind) }
                        }
                    } label: {
                        HStack {
                            Text("Not Owned: \(section.kind.title)")
                            Text(String(section.releases.count)).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                }
                .themedRows()
            }
        }
    }
}

/// Artists like this one, from the server (usually Last.fm), in a row of
/// small round pictures. Open at first; a line above sets it apart from Not
/// Owned, and its header collapses it. One in the library
/// opens their page; one that isn't opens a MusicBrainz search in Safari, and
/// is marked with an arrow (not by color alone).
private struct SimilarArtistsSection: View {
    let library: Library
    let artists: [SimilarArtist]

    @State private var isExpanded = true
    @ScaledMetric private var side: CGFloat = 64

    var body: some View {
        if !artists.isEmpty {
            Section {
                if isExpanded {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(artists) { artist in
                                item(artist)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }
            } header: {
                VStack(spacing: 12) {
                    Divider()
                    Button {
                        withAnimation { isExpanded.toggle() }
                    } label: {
                        HStack {
                            Text("Similar Artists")
                            Text(String(artists.count)).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                }
            }
            .themedRows()
        }
    }

    @ViewBuilder
    private func item(_ artist: SimilarArtist) -> some View {
        if let id = artist.artistID {
            NavigationLink(value: LibraryRoute.artist(id: id)) { tile(artist) }
                .buttonStyle(.plain)
                .accessibilityLabel(artist.name)
        } else if let url = artist.musicBrainzSearch {
            Link(destination: url) { tile(artist) }
                .buttonStyle(.plain)
                .accessibilityLabel("\(artist.name), not in your library")
                .accessibilityHint("Opens on MusicBrainz")
                .contextMenu {
                    let onList = library.wishlist.containsArtist(named: artist.name)
                    Button(onList ? "On Your Wishlist" : "Add to Wishlist", systemImage: onList ? "checkmark" : "tag") {
                        library.wishlist.addArtist(named: artist.name, musicBrainzURL: url)
                    }
                    .disabled(onList)
                }
        }
    }

    private func tile(_ artist: SimilarArtist) -> some View {
        VStack(spacing: 6) {
            picture(artist)
                .frame(width: side, height: side)
                .clipShape(.circle)
                .overlay(alignment: .bottomTrailing) {
                    if !artist.isInLibrary {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, .tint)
                    }
                }
            Text(artist.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(artist.isInLibrary ? .primary : .secondary)
        }
        .frame(width: side + 20)
        .contentShape(.rect)
    }

    @ViewBuilder
    private func picture(_ artist: SimilarArtist) -> some View {
        if artist.isInLibrary, let cover = artist.coverArtID {
            ArtworkView(library: library, coverArtID: cover, side: side)
        } else {
            Image(systemName: "music.microphone")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.fill.secondary)
        }
    }
}

private struct NotOwnedRow: View {
    let library: Library
    let release: DiscographyRelease
    let artistName: String

    var body: some View {
        content
            .contextMenu {
                let onList = library.wishlist.containsAlbum(titled: release.title, by: artistName)
                Button(onList ? "On Your Wishlist" : "Add to Wishlist", systemImage: onList ? "checkmark" : "tag") {
                    library.wishlist.addAlbum(
                        titled: release.title, by: artistName, year: release.year,
                        coverURL: release.coverURL, musicBrainzURL: release.pageURL
                    )
                }
                .disabled(onList)
            }
    }

    @ViewBuilder
    private var content: some View {
        let row = HStack(spacing: 12) {
            ArtworkView(library: library, coverArtID: release.coverURL.map(StationLogo.coverArtID), side: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(release.title).lineLimit(1)
                if let year = release.year {
                    Text(String(year)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        if let url = release.pageURL {
            Link(destination: url) { row.contentShape(.rect) }
                .foregroundStyle(.primary)
        } else {
            row
        }
    }
}
