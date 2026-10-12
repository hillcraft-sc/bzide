import NavidromeCore
import SwiftUI

/// Cover art, with a plain placeholder while it loads or when there is none.
struct ArtworkView: View {
    let library: Library
    let coverArtID: String?
    let side: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: side > 100 ? 12 : 6))
        .accessibilityHidden(true)
        .task(id: coverArtID) {
            image = nil
            guard let coverArtID else { return }
            image = await library.artwork.image(for: coverArtID, pixels: Int(side * displayScale))
        }
    }
}

/// Shows a `LoadState`: a spinner, an error with retry, or the content.
struct LoadStateView<Value, Content: View>: View {
    let state: LoadState<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    @Environment(\.catppuccin) private var palette

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.map { Color($0.base) } ?? .clear)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await retry() } }
            }
            .background(palette.map { Color($0.base) } ?? .clear)
        case .loaded(let value):
            content(value)
        }
    }
}

/// A song in a list. Shows the track number in album order, otherwise the artist.
struct SongRow: View {
    let song: Song
    let isCurrent: Bool
    var showsTrackNumber = false
    /// See `SongMarks`; the caller reads them from the shared models.
    var isFavorite = false
    var rating: Rating?

    var body: some View {
        HStack(spacing: 12) {
            if showsTrackNumber {
                Text(song.track.map(String.init) ?? "")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title.isEmpty ? "Untitled" : song.title)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                if !showsTrackNumber, let artist = song.artist {
                    Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Now playing")
            }
            SongMarks(isFavorite: isFavorite, rating: rating)
            if let duration = song.duration {
                Text(formatDuration(TimeInterval(duration)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }
}

/// A song's favorite heart and rating face, shown in lists. Display only: they're
/// changed from the song's menu, not by tapping these.
struct SongMarks: View {
    let isFavorite: Bool
    let rating: Rating?

    var body: some View {
        HStack(spacing: 4) {
            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Favorite")
            }
            if let rating {
                Text(rating.face)
                    .font(.caption)
                    .accessibilityLabel("Rated \(rating.title)")
            }
        }
    }
}

extension Library {
    /// The heart as the user last set it, in this session or on the server.
    func isFavorite(_ song: Song) -> Bool {
        stars.isStarred(.song(id: song.id), fromServer: song.isStarred)
    }

    /// The rating as the user last set it, in this session or on the server.
    func rating(of song: Song) -> Rating? {
        ratings.rating(.song(id: song.id), fromServer: song.userRating)
    }
}

struct AlbumRow: View {
    let library: Library
    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(library: library, coverArtID: album.coverArtID, side: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name.isEmpty ? "Untitled" : album.name).lineLimit(1)
                Text([album.artist, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Favourite toggle (a Subsonic star). Reads and writes through the shared `StarModel`.
struct FavoriteButton: View {
    let stars: StarModel
    let target: StarTarget
    let fromServer: Bool

    var body: some View {
        let favorite = stars.isStarred(target, fromServer: fromServer)
        Button(favorite ? "Unfavorite" : "Favorite", systemImage: favorite ? "heart.fill" : "heart") {
            Task { await stars.toggle(target, fromServer: fromServer) }
        }
    }
}

/// Meh, Don't Hate It or Rocks, with a checkmark on the current one; choosing it again
/// clears it. Reads and writes through the shared `RatingModel`.
struct RateMenu: View {
    let ratings: RatingModel
    let target: StarTarget
    let fromServer: Int?

    var body: some View {
        let current = ratings.rating(target, fromServer: fromServer)
        Menu(current.map { "Rated: \($0.title)" } ?? "Rate", systemImage: current == nil ? "star" : "star.fill") {
            ForEach(Rating.allCases.reversed(), id: \.self) { rating in
                // A toggle so the menu draws the checkmark; turning the current
                // one off is choosing it again, which clears it.
                Toggle("\(rating.face) \(rating.title)", isOn: Binding(
                    get: { rating == current },
                    set: { _ in Task { await ratings.choose(rating, for: target, fromServer: fromServer) } }
                ))
            }
        }
    }
}

extension Rating {
    /// Shown beside the title in the Rate menu.
    var face: String {
        switch self {
        case .meh: "😩"
        case .dontHateIt: "👌"
        case .rocks: "😈"
        }
    }
}

/// Favourite and rate: the same pair everywhere an item can be marked.
struct MarkActions: View {
    let library: Library
    let target: StarTarget
    let isStarred: Bool
    let userRating: Int?

    var body: some View {
        FavoriteButton(stars: library.stars, target: target, fromServer: isStarred)
        RateMenu(ratings: library.ratings, target: target, fromServer: userRating)
    }
}

/// Song context menu: queue, playlist, download, favourite and rate, and the
/// way to its album and artist.
struct SongActions: View {
    let library: Library
    let song: Song
    /// Off on the song's own album page, where it would lead back to itself.
    var showsGoToAlbum = true

    var body: some View {
        Button("Play Next", systemImage: "text.insert") { library.engine.playNext([song]) }
        Button("Add to Queue", systemImage: "text.append") { library.engine.append([song]) }
        AddToPlaylistButton(library: library, songs: [song])
        SongDownloadButton(downloads: library.downloads, song: song)
        MarkActions(library: library, target: .song(id: song.id), isStarred: song.isStarred, userRating: song.userRating)
        Section {
            if showsGoToAlbum, let albumID = song.albumID {
                NavigationLink(value: LibraryRoute.album(id: albumID)) {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
            if let artistID = song.artistID {
                NavigationLink(value: LibraryRoute.artist(id: artistID)) {
                    Label("Go to Artist", systemImage: "music.microphone")
                }
            }
        }
    }
}

/// Download one song, or remove it. A song already on the phone as part of a
/// downloaded album or playlist shows that instead: it goes when they do.
struct SongDownloadButton: View {
    let downloads: DownloadManager
    let song: Song

    var body: some View {
        switch downloads.membership(ofSong: song.id) {
        case .none:
            Button("Download", systemImage: "arrow.down.circle") {
                downloads.download(DownloadCollection(song: song))
            }
        case .own:
            Button("Remove Download", systemImage: "trash", role: .destructive) {
                downloads.remove(collectionID: DownloadCollection.id(.song, serverID: song.id))
            }
        case .inCollection:
            Button("Downloaded", systemImage: "arrow.down.circle.fill") {}
                .disabled(true)
        }
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: .minuteSecond))
}
