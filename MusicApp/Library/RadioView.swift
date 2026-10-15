import NavidromeCore
import SwiftUI

/// The internet radio stations saved on the server. Tapping one plays it in
/// place of the queue. An admin can add stations (+), and edit or delete them
/// (swipe or long-press); the changes are made on the server, for every client.
struct RadioView: View {
    let library: Library
    @State private var model: RadioStationsModel
    /// The form being shown: a new station, or one being edited.
    @State private var editing: StationEditor.Target?
    @State private var deleting: RadioStation?
    @State private var errorMessage: String?
    @State private var isFinding = false

    init(library: Library) {
        self.library = library
        _model = State(initialValue: library.radioStationsModel())
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { stations in
            List(stations) { station in
                StationRow(library: library, station: station, canEdit: model.canEdit, edit: { editing = .edit(station) }, delete: { deleting = station })
                    .themedRows()
            }
            .listStyle(.plain)
            .themedList()
            .overlay {
                if stations.isEmpty {
                    ContentUnavailableView(
                        "No Radio Stations",
                        systemImage: "headphones.sensor.tag.radiowaves.left.and.right", // dot.radiowaves.left.and.right
                        description: Text(model.canEdit ? "Tap + to add an internet radio station." : "Add internet radio stations in your server's web UI.")
                    )
                }
            }
        }
        .navigationTitle("Radio")
        .toolbar {
            Button("Find Stations", systemImage: "magnifyingglass") { isFinding = true }
            if model.canEdit {
                Button("Add Station", systemImage: "plus") { editing = .new }
            }
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
        } message: { _ in
            Text("It's removed from the server, for every app that uses it.")
        }
        .alert("Couldn't Delete Station", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await model.load() }
        .refreshable { await model.load() }
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
                Image(systemName: "headphones.sensor.tag.radiowaves.left.and.right") // dot.radiowaves.left.and.right
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
