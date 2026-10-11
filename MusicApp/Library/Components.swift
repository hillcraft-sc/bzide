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

    var body: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await retry() } }
            }
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
            if let duration = song.duration {
                Text(formatDuration(TimeInterval(duration)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
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

/// Star toggle for anything starrable. Reads and writes through the shared `StarModel`.
struct StarButton: View {
    let stars: StarModel
    let target: StarTarget
    let fromServer: Bool

    var body: some View {
        let starred = stars.isStarred(target, fromServer: fromServer)
        Button(starred ? "Unstar" : "Star", systemImage: starred ? "star.fill" : "star") {
            Task { await stars.toggle(target, fromServer: fromServer) }
        }
    }
}

/// Song context menu: queue and star.
struct SongActions: View {
    let library: Library
    let song: Song

    var body: some View {
        Button("Add to Queue", systemImage: "text.append") { library.engine.append([song]) }
        StarButton(stars: library.stars, target: .song(id: song.id), fromServer: song.isStarred)
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: .minuteSecond))
}
