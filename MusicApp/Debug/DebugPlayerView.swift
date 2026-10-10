import NavidromeCore
import SwiftUI

/// Bare screen for exercising the playback engine. Not the real UI.
struct DebugPlayerView: View {
    let model: AppModel
    let engine: PlaybackEngine

    var body: some View {
        NavigationStack {
            List {
                Section("Now playing") {
                    TransportControls(engine: engine)
                }
                if let error = model.libraryError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section("Play something") {
                    Button("30 random songs") {
                        Task { await model.playRandomSongs() }
                    }
                }
                Section("Queue (\(engine.queue.entries.count))") {
                    QueueList(engine: engine)
                }
                Section("Newest albums") {
                    ForEach(model.albums) { album in
                        Button {
                            Task { await model.play(album: album) }
                        } label: {
                            TitleRow(title: album.name, subtitle: album.artist)
                        }
                    }
                }
                Section("Playlists") {
                    ForEach(model.playlists) { playlist in
                        Button {
                            Task { await model.play(playlist: playlist) }
                        } label: {
                            TitleRow(title: playlist.name, subtitle: playlist.songCount.map { "\($0) songs" })
                        }
                    }
                }
            }
            .navigationTitle("Debug player")
            .task { await model.loadLibrary() }
            .refreshable { await model.loadLibrary() }
        }
    }
}

struct TitleRow: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text(title.isEmpty ? "Untitled" : title)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
