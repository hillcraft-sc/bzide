import NavidromeCore
import SwiftUI

#if DEBUG
/// Bare screen for exercising the playback engine. Not the real UI. Only in
/// builds Xcode installs (Debug), never TestFlight or the App Store (#24).
struct DebugPlayerView: View {
    let model: AppModel
    let engine: PlaybackEngine
    @State private var isMetering = false

    var body: some View {
        NavigationStack {
            List {
                Section("Now playing") {
                    TransportControls(engine: engine)
                }
                Section {
                    Toggle("Audio tap", isOn: $isMetering)
                    if isMetering {
                        LevelMeterView(meter: model.levelMeter)
                    }
                } header: {
                    Text("Visualizer test")
                } footer: {
                    Text("Taps playback to read live levels. While it's on, check that songs still flow without gaps, that calls and AirPlay behave, and that streamed, downloaded and radio audio all move the bars. Off again at every launch.")
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
            .onAppear { isMetering = model.isMetering }
            .onChange(of: isMetering) { _, on in model.isMetering = on }
            .task { await model.loadLibrary() }
            .refreshable { await model.loadLibrary() }
        }
    }
}

#endif

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

#if DEBUG
/// Left and right level bars, redrawn every frame from the meter, with the
/// tap's buffer count to show it's running.
private struct LevelMeterView: View {
    let meter: AudioLevelMeter

    var body: some View {
        TimelineView(.animation) { _ in
            let levels = meter.levels
            VStack(alignment: .leading, spacing: 6) {
                bar("L", levels.left)
                bar("R", levels.right)
                Text("Buffers: \(meter.bufferCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bar(_ label: String, _ level: Float) -> some View {
        HStack {
            Text(label).font(.caption.monospaced()).frame(width: 14)
            GeometryReader { geometry in
                Capsule()
                    .fill(.tint)
                    // RMS of music sits well below 1; scale up so the bar moves visibly.
                    .frame(width: geometry.size.width * CGFloat(min(level * 2.5, 1)))
            }
            .frame(height: 8)
            Text(String(format: "%.2f", level))
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }
}
#endif
