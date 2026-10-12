import NavidromeCore
import SwiftUI

/// The internet radio stations saved on the server. Tapping one plays it in
/// place of the queue. Stations are added and edited in Navidrome's web UI.
struct RadioView: View {
    let library: Library
    @State private var model: LoadModel<[RadioStation]>

    init(library: Library) {
        self.library = library
        _model = State(initialValue: library.radioStationsModel())
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { stations in
            List(stations) { station in
                StationRow(library: library, station: station)
                    .themedRows()
            }
            .listStyle(.plain)
            .themedList()
            .overlay {
                if stations.isEmpty {
                    ContentUnavailableView(
                        "No Radio Stations",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Add internet radio stations in Navidrome's web UI.")
                    )
                }
            }
        }
        .navigationTitle("Radio")
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

private struct StationRow: View {
    let library: Library
    let station: RadioStation

    @Environment(\.openURL) private var openURL

    private var isCurrent: Bool { library.engine.queue.current?.song.id == station.songID }
    private var isStarting: Bool { library.radio.startingStationID == station.id }

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    if let host = station.streamURL.host() {
                        Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if isStarting {
                    ProgressView()
                } else if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Now playing")
                }
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .contextMenu {
            Button("Play", systemImage: "play.fill", action: play)
            if let homePage = station.homePageURL {
                Button("Open Homepage", systemImage: "safari") { openURL(homePage) }
            }
        }
    }

    private func play() {
        Task { await library.radio.start(station) }
    }
}
