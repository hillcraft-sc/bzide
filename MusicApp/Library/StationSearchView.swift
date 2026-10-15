import NavidromeCore
import SwiftUI

/// Finding stations on Radio Browser: the most played ones until something is
/// typed, then a search by name, genre or country. Tapping a station plays it;
/// an admin can add it to the server with +. Until Find Stations Online is
/// on, it explains what that sends and offers to turn it on.
struct StationSearchView: View {
    let library: Library
    let stations: RadioStationsModel
    @State private var model: StationSearchModel
    @State private var addingID: String?
    @State private var errorMessage: String?

    static let optInExplanation = "Search Radio Browser (radio-browser.info), a free directory of internet radio stations, from Radio > Find Stations. This sends what you search for there, and counts plays of stations you find there toward their popularity."

    init(library: Library, stations: RadioStationsModel) {
        self.library = library
        self.stations = stations
        _model = State(initialValue: library.stationSearchModel())
    }

    private var isOn: Bool { library.settings.settings.findStationsOnline }

    var body: some View {
        Group {
            if isOn {
                results
                    .searchable(text: $model.text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Stations")
                    .searchScopes($model.field) {
                        ForEach(RadioBrowserClient.Field.allCases, id: \.self) { field in
                            Text(field.title).tag(field)
                        }
                    }
                    .task(id: "\(model.text)|\(model.field)") { await model.update() }
            } else {
                optIn
            }
        }
        .navigationTitle("Find Stations")
        .alert("Couldn't Add Station", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var optIn: some View {
        ContentUnavailableView {
            Label("Find Stations Online", systemImage: "magnifyingglass")
        } description: {
            Text(Self.optInExplanation)
        } actions: {
            Button("Turn On") { library.settings.settings.findStationsOnline = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var results: some View {
        LoadStateView(state: model.state, retry: model.update) { found in
            List {
                Section {
                    ForEach(found) { station in
                        FoundStationRow(
                            library: library, station: station,
                            canAdd: stations.canEdit,
                            isAdded: stations.stations.contains { $0.streamURL == station.streamURL },
                            isAdding: addingID == station.id,
                            play: { play(station) },
                            add: { add(station) }
                        )
                    }
                } header: {
                    if model.isShowingPopular && !found.isEmpty { Text("Popular Now") }
                } footer: {
                    if !found.isEmpty { Text("From Radio Browser (radio-browser.info)") }
                }
                .themedRows()
            }
            .listStyle(.plain)
            .themedList()
            .overlay {
                if found.isEmpty {
                    ContentUnavailableView.search(text: model.text)
                }
            }
        }
    }

    private func play(_ station: RadioBrowserStation) {
        model.played(station)
        Task { await library.radio.start(station.radioStation) }
    }

    private func add(_ station: RadioBrowserStation) {
        addingID = station.id
        Task {
            defer { addingID = nil }
            do throws(RadioStationsModel.ChangeError) {
                try await stations.add(station.draft)
            } catch {
                errorMessage = error.message
            }
        }
    }
}

private struct FoundStationRow: View {
    let library: Library
    let station: RadioBrowserStation
    let canAdd: Bool
    let isAdded: Bool
    let isAdding: Bool
    let play: () -> Void
    let add: () -> Void

    @Environment(\.openURL) private var openURL

    private var isCurrent: Bool { library.engine.queue.current?.song.id == station.radioStation.songID }
    private var isStarting: Bool { library.radio.startingStationID == station.radioStation.id }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.name)
                            .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            .lineLimit(1)
                        if !station.summary.isEmpty {
                            Text(station.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
            if canAdd {
                addButton
            }
        }
        .contextMenu {
            Button("Play", systemImage: "play.fill", action: play)
            if canAdd && !isAdded {
                Button("Add to Server", systemImage: "plus", action: add)
            }
            if let homePage = station.homePageURL {
                Button("Open Homepage", systemImage: "safari") { openURL(homePage) }
            }
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if isAdding {
            ProgressView()
        } else if isAdded {
            Image(systemName: "checkmark")
                .foregroundStyle(.secondary)
                .accessibilityLabel("In your stations")
        } else {
            Button("Add to Server", systemImage: "plus.circle", action: add)
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.borderless)
        }
    }
}
