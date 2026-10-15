import Foundation
import Observation

/// The Radio screen's stations, and adding, editing and removing them: the
/// server's, and the ones saved on this iPhone (My Stations).
///
/// Navidrome lets only admins change the server's stations, so that's offered
/// only when the server says the user is one (`getUser`'s `adminRole`); if
/// that can't be checked, it isn't. New stations go to the server for an
/// admin and to this iPhone for everyone else, so anyone can keep stations.
/// Server changes are made there and the list is fetched again, so it always
/// shows what the server has; this iPhone's are saved at once.
@MainActor
@Observable
public final class RadioStationsModel {
    /// What the model needs from the server.
    public struct Sources: Sendable {
        public var stations: @Sendable () async throws(SubsonicError) -> [RadioStation]
        public var isAdmin: @Sendable () async throws(SubsonicError) -> Bool
        public var create: @Sendable (RadioStationDraft.Valid) async throws(SubsonicError) -> Void
        public var update: @Sendable (String, RadioStationDraft.Valid) async throws(SubsonicError) -> Void
        public var delete: @Sendable (String) async throws(SubsonicError) -> Void

        public init(
            stations: @escaping @Sendable () async throws(SubsonicError) -> [RadioStation],
            isAdmin: @escaping @Sendable () async throws(SubsonicError) -> Bool,
            create: @escaping @Sendable (RadioStationDraft.Valid) async throws(SubsonicError) -> Void,
            update: @escaping @Sendable (String, RadioStationDraft.Valid) async throws(SubsonicError) -> Void,
            delete: @escaping @Sendable (String) async throws(SubsonicError) -> Void
        ) {
            self.stations = stations
            self.isAdmin = isAdmin
            self.create = create
            self.update = update
            self.delete = delete
        }
    }

    /// Where a station is saved.
    public enum Place: Sendable {
        case server, phone
    }

    /// Why a change wasn't saved, for an alert.
    public enum ChangeError: Error, Equatable, Sendable {
        case invalid(RadioStationDraft.Problem)
        case server(String)

        public var message: String {
            switch self {
            case .invalid(let problem): problem.message
            case .server(let message): message
            }
        }
    }

    public private(set) var state: LoadState<[RadioStation]> = .loading
    public private(set) var refreshError: String?
    /// Whether the user may add, edit and delete the server's stations.
    public private(set) var canEdit = false
    /// The stations saved on this iPhone, by name.
    public private(set) var phoneStations: [RadioStation]

    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private let phone: PhoneStationStore
    @ObservationIgnored private var isFetching = false
    @ObservationIgnored private var checkedAdmin = false

    public init(sources: Sources, phone: PhoneStationStore) {
        self.sources = sources
        self.phone = phone
        phoneStations = Self.sorted(phone.load())
    }

    /// The server's stations.
    public var stations: [RadioStation] {
        if case .loaded(let stations) = state { stations } else { [] }
    }

    /// Where Add Station saves: the server for an admin, else this iPhone.
    public var newStationPlace: Place { canEdit ? .server : .phone }

    /// Whether a station can be edited and deleted: always on this iPhone;
    /// on the server, only by an admin.
    public func canChange(_ station: RadioStation) -> Bool {
        station.isOnPhone || canEdit
    }

    /// Whether a station with this stream is saved already, in either place.
    public func contains(stream: URL) -> Bool {
        stations.contains { $0.streamURL == stream } || phoneStations.contains { $0.streamURL == stream }
    }

    /// Fetches the stations, sorted by name, and (once) whether the user may
    /// change them. A refresh keeps the list on screen if it fails.
    public func load() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        refreshError = nil
        let hadList = if case .loaded = state { true } else { false }
        if !hadList { state = .loading }
        if !checkedAdmin, let admin = try? await sources.isAdmin() {
            checkedAdmin = true
            canEdit = admin
        }
        do {
            state = .loaded(Self.sorted(try await sources.stations()))
        } catch {
            if Task.isCancelled { return }
            if hadList { refreshError = error.localizedDescription } else { state = .failed(error.localizedDescription) }
        }
    }

    /// Saves a new station, by default where `newStationPlace` says.
    public func add(_ draft: RadioStationDraft, to place: Place? = nil) async throws(ChangeError) {
        let valid = try Self.validate(draft)
        switch place ?? newStationPlace {
        case .server:
            try await change { () async throws(SubsonicError) in try await sources.create(valid) }
        case .phone:
            let station = RadioStation(
                id: RadioStation.phonePrefix + UUID().uuidString, name: valid.name,
                streamURL: valid.streamURL, homePageURL: valid.homePageURL
            )
            savePhone(phoneStations + [station])
        }
    }

    public func update(_ station: RadioStation, to draft: RadioStationDraft) async throws(ChangeError) {
        let valid = try Self.validate(draft)
        if station.isOnPhone {
            let changed = RadioStation(id: station.id, name: valid.name, streamURL: valid.streamURL, homePageURL: valid.homePageURL)
            savePhone(phoneStations.map { $0.id == station.id ? changed : $0 })
            return
        }
        try await change { () async throws(SubsonicError) in try await sources.update(station.id, valid) }
    }

    public func delete(_ station: RadioStation) async throws(ChangeError) {
        if station.isOnPhone {
            savePhone(phoneStations.filter { $0.id != station.id })
            return
        }
        try await change { () async throws(SubsonicError) in try await sources.delete(station.id) }
        // Gone at once, even if the reload below fails.
        if case .loaded(let stations) = state {
            state = .loaded(stations.filter { $0.id != station.id })
        }
    }

    // MARK: - Helpers

    private func savePhone(_ stations: [RadioStation]) {
        phoneStations = Self.sorted(stations)
        phone.save(phoneStations)
    }

    private func change(_ save: () async throws(SubsonicError) -> Void) async throws(ChangeError) {
        do {
            try await save()
        } catch {
            throw .server(Self.message(for: error))
        }
        await load()
    }

    private static func validate(_ draft: RadioStationDraft) throws(ChangeError) -> RadioStationDraft.Valid {
        switch draft.validated() {
        case .success(let valid): return valid
        case .failure(let problem): throw .invalid(problem)
        }
    }

    /// Subsonic error 50 is "not authorized": on Navidrome, not an admin.
    static func message(for error: SubsonicError) -> String {
        if case .server(50, _) = error { return "Only an admin can change the server's radio stations." }
        return error.localizedDescription
    }

    static func sorted(_ stations: [RadioStation]) -> [RadioStation] {
        stations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
