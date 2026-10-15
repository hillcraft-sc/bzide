import Foundation
import Observation

/// The Radio screen's stations, and adding, editing and removing them on the
/// server. Navidrome lets only admins change stations, so editing is offered
/// only when the server says the user is one (`getUser`'s `adminRole`); if
/// that can't be checked, it isn't offered. Changes are made on the server
/// and the list is fetched again, so it always shows what the server has.
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

    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private var isFetching = false
    @ObservationIgnored private var checkedAdmin = false

    public init(sources: Sources) {
        self.sources = sources
    }

    public var stations: [RadioStation] {
        if case .loaded(let stations) = state { stations } else { [] }
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

    public func add(_ draft: RadioStationDraft) async throws(ChangeError) {
        let valid = try Self.validate(draft)
        try await change { () async throws(SubsonicError) in try await sources.create(valid) }
    }

    public func update(_ station: RadioStation, to draft: RadioStationDraft) async throws(ChangeError) {
        let valid = try Self.validate(draft)
        try await change { () async throws(SubsonicError) in try await sources.update(station.id, valid) }
    }

    public func delete(_ station: RadioStation) async throws(ChangeError) {
        try await change { () async throws(SubsonicError) in try await sources.delete(station.id) }
        // Gone at once, even if the reload below fails.
        if case .loaded(let stations) = state {
            state = .loaded(stations.filter { $0.id != station.id })
        }
    }

    // MARK: - Helpers

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
