import NavidromeCore
import SwiftUI

/// Finding stations on Radio Browser: what's popular until a name is typed or
/// a filter is chosen, then the matching stations, 50 at a time with more as
/// the list reaches its end. Country, Genre and the order are in a bar under
/// the search field. Tapping a station plays it; + saves it (to the server for
/// an admin, else to this iPhone). Until Find Stations Online is on, it explains what that
/// sends and offers to turn it on.
struct StationSearchView: View {
    let library: Library
    let stations: RadioStationsModel
    @State private var model: StationSearchModel
    @State private var addingID: String?
    @State private var errorMessage: String?
    @State private var picking: FilterKind?
    /// A station the server refused, and why: offered for this iPhone instead.
    @State private var refused: (station: RadioBrowserStation, reason: String)?

    static let optInExplanation = "Search Radio Browser (radio-browser.info), a free directory of internet radio stations, from Radio > Find Stations. This sends what you search for and the filters you choose there, and counts plays of stations you find there toward their popularity."

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
                    .searchable(text: $model.query.name, placement: .navigationBarDrawer(displayMode: .always), prompt: "Station Name")
                    .safeAreaInset(edge: .top, spacing: 0) { filterBar }
                    .task(id: model.query) { await model.update() }
            } else {
                optIn
            }
        }
        .navigationTitle("Find Stations")
        .sheet(item: $picking) { kind in
            switch kind {
            case .country: CountryPicker(model: model)
            case .genre: GenrePicker(model: model)
            }
        }
        .alert("Couldn't Save to Server", isPresented: Binding(get: { refused != nil }, set: { if !$0 { refused = nil } })) {
            Button("Save on This iPhone") {
                if let station = refused?.station { add(station, to: .phone) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(refused?.reason ?? "")\n\nSave it on this iPhone instead?")
        }
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

    // MARK: - Filters

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterButton(
                    title: model.query.countryCode.map { RadioBrowserClient.Country(code: $0, stationCount: 0).name() } ?? "Country",
                    isSet: model.query.countryCode != nil
                ) { picking = .country }
                FilterButton(title: model.query.tag ?? "Genre", isSet: model.query.tag != nil) { picking = .genre }
                Menu {
                    Picker("Sort By", selection: $model.query.order) {
                        ForEach(RadioBrowserClient.Order.allCases, id: \.self) { order in
                            Text(order.title).tag(order)
                        }
                    }
                } label: {
                    FilterLabel(title: model.query.order.title, systemImage: "arrow.up.arrow.down", isSet: false)
                }
                if model.query.countryCode != nil || model.query.tag != nil {
                    Button("Clear Filters", systemImage: "xmark.circle.fill") {
                        model.query.countryCode = nil
                        model.query.tag = nil
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }

    // MARK: - Results

    private var results: some View {
        LoadStateView(state: model.state, retry: model.update) { found in
            List {
                Section {
                    ForEach(found) { station in
                        FoundStationRow(
                            library: library, station: station,
                            addTitle: stations.newStationPlace == .server ? "Add to Server" : "Add to My Stations",
                            isAdded: stations.contains(stream: station.streamURL),
                            isAdding: addingID == station.id,
                            play: { play(station) },
                            add: { add(station) }
                        )
                        .onAppear {
                            if station.id == found.last?.id { Task { await model.loadMore() } }
                        }
                    }
                    if model.hasMore {
                        moreRow
                    }
                } header: {
                    if model.isShowingPopular && !found.isEmpty { Text("Popular Now") }
                } footer: {
                    if !found.isEmpty && !model.hasMore { Text("From Radio Browser (radio-browser.info)") }
                }
                .themedRows()
            }
            .listStyle(.plain)
            .themedList()
            .overlay {
                if found.isEmpty {
                    if model.query.name.isEmpty {
                        ContentUnavailableView("No Stations", systemImage: "magnifyingglass", description: Text("No stations match these filters."))
                    } else {
                        ContentUnavailableView.search(text: model.query.name)
                    }
                }
            }
        }
    }

    /// The end of the list while more may follow: a spinner, or why the next
    /// page didn't load with a retry.
    @ViewBuilder
    private var moreRow: some View {
        if let error = model.moreError {
            Button {
                Task { await model.loadMore() }
            } label: {
                Label(error, systemImage: "arrow.clockwise")
                    .font(.footnote)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .onAppear { Task { await model.loadMore() } }
        }
    }

    private func play(_ station: RadioBrowserStation) {
        model.played(station)
        Task { await library.radio.start(station.radioStation) }
    }

    private func add(_ station: RadioBrowserStation, to place: RadioStationsModel.Place? = nil) {
        addingID = station.id
        let place = place ?? stations.newStationPlace
        Task {
            defer { addingID = nil }
            do throws(RadioStationsModel.ChangeError) {
                try await stations.add(station.draft, to: place)
            } catch {
                if case .server(let reason) = error, place == .server {
                    refused = (station, reason)
                } else {
                    errorMessage = error.message
                }
            }
        }
    }
}

private enum FilterKind: String, Identifiable {
    case country, genre
    var id: String { rawValue }
}

/// A filter in the bar: its value when one is chosen, tinted.
private struct FilterButton: View {
    let title: String
    let isSet: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FilterLabel(title: title, systemImage: "chevron.down", isSet: isSet)
        }
    }
}

private struct FilterLabel: View {
    let title: String
    let systemImage: String
    let isSet: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            Image(systemName: systemImage).imageScale(.small)
        }
        .font(.subheadline.weight(isSet ? .semibold : .regular))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(isSet ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .background(isSet ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
    }
}

// MARK: - Pickers

/// Choosing a country: the phone's own country first, then every country with
/// stations, most first, searchable by name.
private struct CountryPicker: View {
    let model: StationSearchModel

    var body: some View {
        FilterPicker(
            title: "Country",
            anyTitle: "Any Country",
            state: model.countries,
            load: model.loadCountries,
            selection: model.query.countryCode,
            option: { FilterOption(id: $0.code, title: $0.name(), count: $0.stationCount) },
            pinnedID: Locale.current.region?.identifier,
            pinnedTitle: "Your Country",
            choose: { model.query.countryCode = $0 }
        )
    }
}

/// Choosing a genre: Radio Browser's most common tags, searchable.
private struct GenrePicker: View {
    let model: StationSearchModel

    var body: some View {
        FilterPicker(
            title: "Genre",
            anyTitle: "Any Genre",
            state: model.tags,
            load: model.loadTags,
            selection: model.query.tag,
            option: { FilterOption(id: $0.name, title: $0.name, count: $0.stationCount) },
            pinnedID: nil,
            pinnedTitle: nil,
            choose: { model.query.tag = $0 }
        )
    }
}

private struct FilterOption: Identifiable {
    let id: String
    let title: String
    let count: Int
}

/// A searchable list to pick one filter value from, or Any.
private struct FilterPicker<Item>: View {
    let title: String
    let anyTitle: String
    let state: LoadState<[Item]>
    let load: () async -> Void
    let selection: String?
    let option: (Item) -> FilterOption
    /// Shown above the rest under `pinnedTitle`, if it's in the list.
    let pinnedID: String?
    let pinnedTitle: String?
    let choose: (String?) -> Void

    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoadStateView(state: state, retry: load) { items in
                let options = items.map(option)
                let shown = search.isEmpty ? options : options.filter { $0.title.localizedStandardContains(search) }
                List {
                    if search.isEmpty {
                        Section {
                            row(id: nil, title: anyTitle, count: nil)
                        }
                        if let pinnedTitle, let pinned = options.first(where: { $0.id == pinnedID }) {
                            Section(pinnedTitle) {
                                row(id: pinned.id, title: pinned.title, count: pinned.count)
                            }
                        }
                    }
                    Section {
                        ForEach(shown) { row(id: $0.id, title: $0.title, count: $0.count) }
                    }
                }
                .overlay {
                    if shown.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func row(id: String?, title: String, count: Int?) -> some View {
        Button {
            choose(id)
            dismiss()
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if let count {
                    Text(count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                }
                if id == selection {
                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Selected")
                }
            }
            .contentShape(.rect)
        }
    }
}

private struct FoundStationRow: View {
    let library: Library
    let station: RadioBrowserStation
    let addTitle: String
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
            addButton
        }
        .contextMenu {
            Button("Play", systemImage: "play.fill", action: play)
            if !isAdded {
                Button(addTitle, systemImage: "plus", action: add)
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
            Button(addTitle, systemImage: "plus.circle", action: add)
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.borderless)
        }
    }
}
