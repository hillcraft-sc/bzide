import AppIntents
import NavidromeCore
import SwiftUI
import WidgetKit

/// Four buttons to start music without opening Bzide: Continue (the queue,
/// named on the medium size), Random Mix, Mix My Cuts, and Favorite (the
/// playing song; filled when it's a favorite). Like the Home Screen quick
/// actions, through audio playback intents run in the app. It reads the same
/// snapshot as the Now Playing widget, to name what Continue continues and
/// to know what can be pressed.
struct ShortcutsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.shortcuts, provider: NowPlayingProvider()) { entry in
            ShortcutsWidgetView(snapshot: entry.snapshot)
                .themedWidget(entry.theme)
        }
        .configurationDisplayName("Shortcuts")
        .description("Continue, Random Mix, Mix My Cuts and Favorite.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ShortcutsWidgetView: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    private var isMedium: Bool { family == .systemMedium }

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Tile(intent: ContinuePlaybackIntent(), title: "Continue", detail: continueDetail, systemImage: "play.fill", isMedium: isMedium)
                    // Nothing to continue, or it's playing already.
                    .disabled(snapshot == nil || snapshot?.isPlaying == true)
                Tile(intent: RandomMixIntent(), title: "Random Mix", systemImage: "shuffle", isMedium: isMedium)
            }
            GridRow {
                Tile(intent: MixMyCutsIntent(), title: "Mix My Cuts", systemImage: "flame", isMedium: isMedium)
                favorite
            }
        }
    }

    /// "Paranoid Android · Radiohead", or "Playing" while it plays.
    private var continueDetail: String? {
        guard let snapshot else { return nil }
        if snapshot.isPlaying { return "Playing" }
        return [snapshot.title, snapshot.subtitle].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var favorite: some View {
        if snapshot?.isFavorite == true {
            Tile(intent: UnfavoriteCurrentSongIntent(), title: "Favorite", systemImage: "heart.fill", isMedium: isMedium)
        } else {
            Tile(intent: FavoriteCurrentSongIntent(), title: "Favorite", systemImage: "heart", isMedium: isMedium)
                // No song playing (nothing, or a station).
                .disabled(snapshot?.isFavorite == nil)
        }
    }
}

private struct Tile<Intent: AppIntent>: View {
    let intent: Intent
    let title: String
    var detail: String?
    let systemImage: String
    let isMedium: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.widgetSurface) private var surface

    var body: some View {
        Button(intent: intent) {
            Group {
                if isMedium {
                    HStack(spacing: 8) {
                        Image(systemName: systemImage).font(.title3).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title).font(.subheadline.bold()).lineLimit(1)
                            if let detail {
                                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: systemImage).font(.title3).foregroundStyle(.tint)
                        Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(surface.map(AnyShapeStyle.init) ?? AnyShapeStyle(.fill.secondary), in: .rect(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}
