import NavidromeCore
import SwiftUI

/// The internet radio stations saved on the server and on this iPhone, in two
/// sections when there are both, searchable by name and filtered and sorted
/// like Find Stations (country, genre, quality; name, country, quality or
/// date added), the filters remembered on this device. Tapping one plays it
/// in place of the queue.
/// + adds a station (to the server for an admin, else to this iPhone); swipe
/// or long-press edits or deletes one. Server stations can be changed only by
/// an admin, and the change is for every client.
struct RadioView: View {
    let library: Library
    @State private var model: RadioStationsModel
    /// The form being shown: a new station, or one being edited.
    @State private var editing: StationEditor.Target?
    @State private var deleting: RadioStation?
    @State private var errorMessage: String?
    @State private var isFinding = false
    @State private var filter = SavedStationsFilter()
    @State private var picking: FilterKind?
    /// The filters and order, kept on this device.
    @AppStorage("savedStationsFilter") private var savedFilter = Data()

    init(library: Library) {
        self.library = library
        _model = State(initialValue: library.radioStationsModel())
    }

    var body: some View {
        FilterBarStack(showsBar: !model.stations.isEmpty || !model.phoneStations.isEmpty) {
            filterBar
        } content: {
            LoadStateView(state: model.state, retry: model.load) { allServer in
                let allPhone = model.phoneStations
                let stations = filter.apply(allServer, countryName: Self.countryName)
                let phone = filter.apply(allPhone, countryName: Self.countryName)
                // Headings only when there's something in both places.
                let showsPlaces = !stations.isEmpty && !phone.isEmpty
                List {
                    if !stations.isEmpty {
                        Section {
                            rows(stations)
                        } header: {
                            if showsPlaces { Text("Server") }
                        }
                        .themedRows()
                    }
                    if !phone.isEmpty {
                        Section {
                            rows(phone)
                        } header: {
                            if showsPlaces { Text("This iPhone") }
                        }
                        .themedRows()
                    }
                }
                .listStyle(.plain)
                .themedList()
                .overlay {
                    if allServer.isEmpty && allPhone.isEmpty {
                        ContentUnavailableView(
                            "No Radio Stations",
                            systemImage: "headphones.sensor.tag.radiowaves.left.and.right", // dot.radiowaves.left.and.right
                            description: Text("Tap + to add an internet radio station, or the magnifying glass to find one.")
                        )
                    } else if stations.isEmpty && phone.isEmpty {
                        ContentUnavailableView(
                            "No Matching Stations",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text(filter.hasFilters
                                ? "Country, genre and quality are known for stations added from Find Stations, or looked up while Find Stations Online is on."
                                : "No saved station has that name.")
                        )
                    }
                }
            }
        }
        .searchable(text: $filter.name, placement: .navigationBarDrawer(displayMode: .always), prompt: "Saved Stations")
        .sheet(item: $picking) { kind in
            picker(kind, stations: model.stations + model.phoneStations)
        }
        .onAppear {
            if let saved = try? JSONDecoder().decode(SavedStationsFilter.self, from: savedFilter) { filter = saved }
        }
        .onChange(of: filter) {
            savedFilter = (try? JSONEncoder().encode(filter)) ?? Data()
        }
        .navigationTitle("Radio")
        .toolbar {
            Button("Find Stations", systemImage: "magnifyingglass") { isFinding = true }
            Button("Add Station", systemImage: "plus") { editing = .new }
        }
        .navigationDestination(isPresented: $isFinding) {
            StationSearchView(library: library, stations: model)
        }
        .sheet(item: $editing) { target in
            StationEditor(model: model, target: target)
        }
        .confirmationDialog(
            "Delete \u{201C}\(deleting?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { station in
            Button("Delete Station", role: .destructive) { delete(station) }
        } message: { station in
            Text(station.isOnPhone ? "It's removed from this iPhone." : "It's removed from the server, for every app that uses it.")
        }
        .alert("Couldn't Delete Station", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: library.settings.settings.findStationsOnline) {
            model.findsDetailsOnline = library.settings.settings.findStationsOnline
            await model.load()
            await model.findMissingDetails()
        }
        .refreshable { await model.load() }
    }

    // MARK: - Filters

    private var filterBar: some View {
        StationFilterBar(
            country: filter.countryCode.map(Self.countryName),
            genre: filter.tag,
            minimumBitrate: $filter.minimumBitrate,
            order: $filter.sort, orders: SavedStationsFilter.Sort.allCases, orderTitle: { $0.title },
            pickCountry: { picking = .country },
            pickGenre: { picking = .genre },
            clear: { filter.clearFilters() }
        )
    }

    /// Only the countries and genres the saved stations have, with counts.
    @ViewBuilder
    private func picker(_ kind: FilterKind, stations: [RadioStation]) -> some View {
        switch kind {
        case .country:
            FilterPicker(
                title: "Country", anyTitle: "Any Country",
                state: .loaded(SavedStationsFilter.countries(in: stations)), load: {},
                selection: filter.countryCode,
                option: { FilterOption(id: $0.code, title: $0.name(), count: $0.stationCount) },
                pinnedID: Locale.current.region?.identifier, pinnedTitle: "Your Country",
                choose: { filter.countryCode = $0 }
            )
        case .genre:
            FilterPicker(
                title: "Genre", anyTitle: "Any Genre",
                state: .loaded(SavedStationsFilter.tags(in: stations)), load: {},
                selection: filter.tag,
                option: { FilterOption(id: $0.name, title: $0.name, count: $0.stationCount) },
                pinnedID: nil, pinnedTitle: nil,
                choose: { filter.tag = $0 }
            )
        }
    }

    static func countryName(_ code: String) -> String {
        RadioBrowserClient.Country(code: code, stationCount: 0).name()
    }

    private func rows(_ stations: [RadioStation]) -> some View {
        ForEach(stations) { station in
            StationRow(
                library: library, station: station, canEdit: model.canChange(station),
                edit: { editing = .edit(station) }, delete: { deleting = station }
            )
        }
    }

    private func delete(_ station: RadioStation) {
        Task {
            do throws(RadioStationsModel.ChangeError) {
                try await model.delete(station)
            } catch {
                errorMessage = error.message
            }
        }
    }
}

private struct StationRow: View {
    let library: Library
    let station: RadioStation
    let canEdit: Bool
    let edit: () -> Void
    let delete: () -> Void

    @Environment(\.openURL) private var openURL

    private var isCurrent: Bool { library.engine.queue.current?.song.id == station.songID }
    private var isStarting: Bool { library.radio.startingStationID == station.id }

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                StationLogoView(library: library, coverArtID: station.coverArtID)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    // What's known about it (country, quality, genres), else where it streams from.
                    if let summary = station.details?.summary, !summary.isEmpty {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else if let host = station.streamURL.host() {
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
            Button("Station Info", systemImage: "info.circle") {
                library.info.open(.station(StationInfoSubject(station), playing: nil))
            }
            if let homePage = station.homePageURL {
                Button("Open Homepage", systemImage: "safari") { openURL(homePage) }
            }
            if canEdit {
                Button("Edit", systemImage: "pencil", action: edit)
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            }
        }
        .swipeActions {
            if canEdit {
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                Button("Edit", systemImage: "pencil", action: edit)
            }
        }
    }

    private func play() {
        Task { await library.radio.start(station) }
    }
}

/// A station's logo, or the radio symbol without one.
struct StationLogoView: View {
    let library: Library
    let coverArtID: String?

    static let symbol = "headphones.sensor.tag.radiowaves.left.and.right" // dot.radiowaves.left.and.right

    var body: some View {
        if let coverArtID {
            ArtworkView(library: library, coverArtID: coverArtID, side: 40, placeholder: Self.symbol)
        } else {
            Image(systemName: Self.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
        }
    }
}
