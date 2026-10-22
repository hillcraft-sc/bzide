import AppIntents
import NavidromeCore
import SwiftUI
import WidgetKit

/// What's playing in Bzide, from the snapshot the app shares (`WidgetSnapshot`):
/// the cover, title and artist, with play/pause, and on the medium size
/// previous, next and favorite too. The buttons run in the app; the app
/// reloads the widget when anything shown changes, so there's no schedule.
struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.nowPlaying, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .themedWidget(entry.theme)
                .widgetURL(WidgetLinks.nowPlaying)
        }
        .configurationDisplayName("Now Playing")
        .description("What's playing in Bzide, with play and pause.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    /// `nil`: nothing queued.
    let snapshot: WidgetSnapshot?
    let artwork: UIImage?
    /// The app's theme, if it has shared one.
    var theme: WidgetTheme?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snapshot: WidgetSnapshot(title: "Song Title", subtitle: "Artist", isPlaying: false), artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> NowPlayingEntry {
        let store = WidgetSnapshotStore.shared()
        let snapshot = store.read()
        // The artwork only if the snapshot says it's this song's.
        let artwork = snapshot?.coverArtID == nil ? nil : store.readArtwork().flatMap(UIImage.init(data:))
        return NowPlayingEntry(date: .now, snapshot: snapshot, artwork: artwork, theme: store.readTheme())
    }
}

struct NowPlayingWidgetView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemMedium: medium(snapshot)
            case .accessoryRectangular: rectangular(snapshot)
            default: small(snapshot)
            }
        } else {
            nothingPlaying
        }
    }

    private func small(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Cover(image: entry.artwork, isLive: snapshot.isLive)
                    .frame(width: 64, height: 64)
                Spacer(minLength: 4)
                PlayPauseButton(isPlaying: snapshot.isPlaying)
            }
            Spacer(minLength: 0)
            Titles(snapshot: snapshot)
        }
    }

    private func medium(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 12) {
            Cover(image: entry.artwork, isLive: snapshot.isLive)
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 4) {
                Titles(snapshot: snapshot)
                Spacer(minLength: 0)
                HStack {
                    if !snapshot.isLive {
                        Button(intent: PreviousTrackIntent()) { Image(systemName: "backward.fill") }
                        Spacer()
                    }
                    PlayPauseButton(isPlaying: snapshot.isPlaying)
                    Spacer()
                    Button(intent: NextTrackIntent()) { Image(systemName: "forward.fill") }
                        .disabled(!snapshot.hasNext)
                    if let isFavorite = snapshot.isFavorite {
                        Spacer()
                        FavoriteButton(isFavorite: isFavorite)
                    }
                }
                .font(.title3)
                .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
    }

    private func rectangular(_ snapshot: WidgetSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(snapshot.title).font(.headline).lineLimit(1)
                if let subtitle = snapshot.subtitle {
                    Text(subtitle).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            PlayPauseButton(isPlaying: snapshot.isPlaying)
        }
    }

    private var nothingPlaying: some View {
        VStack(alignment: .leading, spacing: 4) {
            if family != .accessoryRectangular {
                Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text("Not Playing").font(.headline)
            Text("Open Bzide to play something.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct Titles: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.title).font(.headline).lineLimit(2)
            if let subtitle = snapshot.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct Cover: View {
    let image: UIImage?
    let isLive: Bool
    @Environment(\.widgetSurface) private var surface

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: isLive ? "dot.radiowaves.left.and.right" : "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(surface.map(AnyShapeStyle.init) ?? AnyShapeStyle(.fill.secondary))
            }
        }
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct PlayPauseButton: View {
    let isPlaying: Bool

    var body: some View {
        Button(intent: TogglePlaybackIntent()) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
        .buttonStyle(.plain)
    }
}

private struct FavoriteButton: View {
    let isFavorite: Bool

    var body: some View {
        if isFavorite {
            Button(intent: UnfavoriteCurrentSongIntent()) {
                Image(systemName: "heart.fill").accessibilityLabel("Unfavorite")
            }
        } else {
            Button(intent: FavoriteCurrentSongIntent()) {
                Image(systemName: "heart").accessibilityLabel("Favorite")
            }
        }
    }
}
