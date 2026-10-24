import NavidromeCore
import SwiftUI

/// Cover art, with a plain placeholder while it loads or when there is none.
struct ArtworkView: View {
    let library: Library
    let coverArtID: String?
    let side: CGFloat
    /// Shown while it loads or when there's none.
    var placeholder = "music.note"

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    /// The cover `image` is of, so a size change keeps it showing while a
    /// sharper copy loads.
    @State private var shownID: String?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: placeholder).foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: side > 100 ? 12 : 6))
        .accessibilityHidden(true)
        // Again when the size changes (a cover sized to its space), at the new
        // size; only a new cover clears the old one first.
        .task(id: "\(coverArtID ?? "")|\(Int(side * displayScale))") {
            if shownID != coverArtID {
                image = nil
                shownID = coverArtID
            }
            guard let coverArtID else { return }
            let loaded = await library.artwork.image(for: coverArtID, pixels: Int(side * displayScale))
            // Shown something else meanwhile (a reused row, a skipped song): this
            // image is for the old one, so it must not overwrite the new.
            guard !Task.isCancelled, let loaded else { return }
            image = loaded
        }
    }
}

/// Shows a `LoadState`: a spinner, an error with retry, or the content.
struct LoadStateView<Value, Content: View>: View {
    let state: LoadState<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    @Environment(\.themePalette) private var palette

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
    var stars: Int?

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
            SongMarks(isFavorite: isFavorite, stars: stars)
            if let duration = song.duration {
                Text(formatDuration(TimeInterval(duration)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }
}

/// A song's favorite heart and rating, shown in lists. Display only: they're
/// changed from the song's menu, not by tapping these.
struct SongMarks: View {
    let isFavorite: Bool
    let stars: Int?

    var body: some View {
        HStack(spacing: 4) {
            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Favorite")
            }
            RatingMark(stars: stars)
        }
    }
}

extension Library {
    /// The heart as the user last set it, in this session or on the server.
    func isFavorite(_ song: Song) -> Bool {
        stars.isStarred(.song(id: song.id), fromServer: song.isStarred)
    }

    /// The rating (1–5 stars) as the user last set it, in this session or on the server.
    func stars(of song: Song) -> Int? {
        ratings.stars(.song(id: song.id), fromServer: song.userRating)
    }
}

struct AlbumRow: View {
    let library: Library
    let album: Album
    /// What's missing, e.g. "9 of 12 tracks" (see `AlbumCompleteness`).
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(library: library, coverArtID: album.coverArtID, side: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name.isEmpty ? "Untitled" : album.name).lineLimit(1)
                Text([album.artist, album.year.map(String.init), badge].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Favorite toggle (a Subsonic star). Reads and writes through the shared `StarModel`.
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

/// Favorite and rate: the same pair everywhere an item can be marked.
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

/// Song context menu: queue, playlist, download, favorite and rate, and the
/// way to its album and artist.
struct SongActions: View {
    let library: Library
    let song: Song
    /// Off on the song's own album page, where it would lead back to itself.
    var showsGoToAlbum = true

    var body: some View {
        Button("Play Next", systemImage: "text.insert") { library.engine.playNext([song]) }
        Button("Add to Queue", systemImage: "text.append") { library.engine.append([song]) }
        SpinOffButton(library: library, song: song)
        AddToPlaylistButton(library: library, songs: [song])
        SongDownloadButton(downloads: library.downloads, song: song)
        MarkActions(library: library, target: .song(id: song.id), isStarred: song.isStarred, userRating: song.userRating)
        SongInfoButton(library: library, song: song)
        Section {
            SongGoToLinks(song: song, showsGoToAlbum: showsGoToAlbum)
        }
    }
}

/// Go to Album and Go to Artist, when the server gave their ids. In menus
/// on song rows and in Now Playing, which open them in their own navigation.
struct SongGoToLinks: View {
    let song: Song
    var showsGoToAlbum = true

    var body: some View {
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

/// Color swatches in rows of seven, each ticked when selected. Used for the
/// accent pickers and the visualizer's custom colors.
struct SwatchGrid<Option: Hashable>: View {
    let options: [Option]
    let color: (Option) -> Color
    let title: (Option) -> String
    let isSelected: (Option) -> Bool
    /// Drawn on a selected swatch; pick one that shows on the swatch colors.
    let checkmark: Color
    let choose: (Option) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(options, id: \.self) { option in
                let selected = isSelected(option)
                Button {
                    choose(option)
                } label: {
                    Circle()
                        .fill(color(option))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.footnote.bold())
                                    .foregroundStyle(checkmark)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// "Spin Off": plays the song, then endless music grown from it.
struct SpinOffButton: View {
    let library: Library
    let song: Song

    var body: some View {
        Button("Spin Off", systemImage: "opticaldisc") {
            Task { await library.spinOff.start(from: song) }
        }
        .disabled(song.isLive)
    }
}

extension View {
    /// A short message that drops in at the top, is read out by VoiceOver,
    /// and goes away after `seconds` or when tapped.
    func noticeBanner(_ message: String?, seconds: Double = 3, dismiss: @escaping () -> Void) -> some View {
        modifier(NoticeBanner(message: message, seconds: seconds, dismiss: dismiss))
    }
}

private struct NoticeBanner: ViewModifier {
    let message: String?
    let seconds: Double
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect()
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { dismiss() }
                    .task(id: message) {
                        AccessibilityNotification.Announcement(message).post()
                        try? await Task.sleep(for: .seconds(seconds))
                        withAnimation { dismiss() }
                    }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.default, value: message)
    }
}

/// Icon and title side by side, the title wrapping in its own column. At the
/// accessibility text sizes the standard style lets a long title wrap back
/// under the icon.
struct WrappingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.icon
            configuration.title
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
