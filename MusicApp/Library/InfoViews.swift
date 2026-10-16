import NavidromeCore
import Observation
import SwiftUI

/// What the Info sheet is open for. Menus anywhere set it; the screen on top
/// presents the sheet (`infoSheet`), as with Add to Playlist.
@MainActor
@Observable
final class InfoRequest {
    enum Target: Identifiable {
        case song(Song)
        case album(id: String)
        /// `playing` is the address being streamed, if it's playing.
        case station(StationInfoSubject, playing: URL?)

        var id: String {
            switch self {
            case .song(let song): "song:\(song.id)"
            case .album(let id): "album:\(id)"
            case .station(let subject, _): "station:\(subject.stream.absoluteString)"
            }
        }
    }

    var pending: Target?

    func open(_ target: Target) {
        pending = target
    }
}

/// "Info" in a song's menus. Radio stations have none.
struct SongInfoButton: View {
    let library: Library
    let song: Song

    var body: some View {
        Button("Song Info", systemImage: "info.circle") { library.info.open(.song(song)) }
            .disabled(song.isLive)
    }
}

/// "Album Info" in an album's menus.
struct AlbumInfoButton: View {
    let library: Library
    let albumID: String

    var body: some View {
        Button("Album Info", systemImage: "info.circle") { library.info.open(.album(id: albumID)) }
    }
}

extension View {
    /// Presents the Info sheet when a menu asks for it. Only the screen on top
    /// may present, so `isEnabled` is false while it's covered (Now Playing
    /// presents its own).
    func infoSheet(_ library: Library, isEnabled: Bool = true) -> some View {
        sheet(item: Binding(
            get: { isEnabled ? library.info.pending : nil },
            set: { if isEnabled { library.info.pending = $0 } }
        )) { target in
            switch target {
            case .song(let song): SongInfoView(library: library, song: song)
            case .album(let id): AlbumInfoView(library: library, id: id)
            case .station(let subject, let playing): StationInfoView(library: library, subject: subject, playing: playing)
            }
        }
    }
}

/// Everything the server says about a song. Shows what's at hand straight
/// away, then the server's latest (play count and so on).
private struct SongInfoView: View {
    let library: Library
    let song: Song
    @State private var model: LoadModel<Song>

    init(library: Library, song: Song) {
        self.library = library
        self.song = song
        _model = State(initialValue: library.songModel(id: song.id))
    }

    var body: some View {
        let shown = model.value ?? song
        InfoList(
            library: library, title: "Song Info", coverArtID: shown.coverArtID,
            heading: shown.title, subheading: shown.artist,
            sections: MediaInfo.sections(for: shown)
        )
        .task { await model.load() }
    }
}

/// Everything the server says about an album.
private struct AlbumInfoView: View {
    let library: Library
    @State private var model: LoadModel<Album>

    init(library: Library, id: String) {
        self.library = library
        _model = State(initialValue: library.albumModel(id: id))
    }

    var body: some View {
        Group {
            if let album = model.value {
                InfoList(
                    library: library, title: "Album Info", coverArtID: album.coverArtID,
                    heading: album.name, subheading: album.artist,
                    sections: MediaInfo.sections(for: album)
                )
            } else {
                NavigationStack {
                    LoadStateView(state: model.state, retry: model.load) { _ in EmptyView() }
                        .navigationTitle("Album Info")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .task { await model.load() }
    }
}

/// Everything known about a radio station: what Bzide knows straight away,
/// then Radio Browser's listing (with Find Stations Online on) and the
/// stream's own description as they arrive.
private struct StationInfoView: View {
    let library: Library
    let subject: StationInfoSubject
    let playing: URL?
    @State private var model: StationInfoModel

    init(library: Library, subject: StationInfoSubject, playing: URL?) {
        self.library = library
        self.subject = subject
        self.playing = playing
        _model = State(initialValue: library.stationInfoModel())
    }

    var body: some View {
        InfoList(
            library: library, title: "Station Info", coverArtID: subject.coverArtID,
            heading: subject.name, subheading: model.isLoading ? "Looking up…" : nil,
            sections: StationInfo.sections(for: subject, listing: model.listing, headers: model.headers)
        )
        .task { await model.load(subject, playing: playing, lookUpOnline: library.settings.settings.findStationsOnline) }
    }
}

/// The sheet itself: the cover and name, then each section's rows.
private struct InfoList: View {
    let library: Library
    let title: String
    let coverArtID: String?
    let heading: String
    let subheading: String?
    let sections: [InfoSection]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ArtworkView(library: library, coverArtID: coverArtID, side: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(heading.isEmpty ? "Untitled" : heading).font(.headline)
                            if let subheading {
                                Text(subheading).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .themedRows(grouped: true)
                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.rows, id: \.label) { row in
                            LabeledContent(row.label) {
                                Text(row.value)
                                    .multilineTextAlignment(.trailing)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .themedRows(grouped: true)
                }
            }
            .themedList(grouped: true)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Full height: it's a screen to read, not glance at.
        .presentationDetents([.large])
    }
}
