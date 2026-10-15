import Foundation
import Observation

/// Finding stations on Radio Browser for the Find Stations screen. Before
/// anything is typed it shows the most played stations; typing searches by
/// name, genre or country once the user pauses. A newer search always wins:
/// a slow answer for older text is dropped. Only used once the user has
/// turned on Find Stations Online.
@MainActor
@Observable
public final class StationSearchModel {
    public struct Sources: Sendable {
        public var search: @Sendable (String, RadioBrowserClient.Field) async throws -> [RadioBrowserStation]
        public var popular: @Sendable () async throws -> [RadioBrowserStation]
        public var countPlay: @Sendable (String) async throws -> Void

        public init(
            search: @escaping @Sendable (String, RadioBrowserClient.Field) async throws -> [RadioBrowserStation],
            popular: @escaping @Sendable () async throws -> [RadioBrowserStation],
            countPlay: @escaping @Sendable (String) async throws -> Void
        ) {
            self.search = search
            self.popular = popular
            self.countPlay = countPlay
        }
    }

    public var text = ""
    public var field: RadioBrowserClient.Field = .name
    public private(set) var state: LoadState<[RadioBrowserStation]> = .loading

    /// The pause after typing before searching.
    @ObservationIgnored private let pause: Duration
    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private var popular: [RadioBrowserStation]?
    @ObservationIgnored private var generation = 0

    public init(sources: Sources, pause: Duration = .milliseconds(400)) {
        self.sources = sources
        self.pause = pause
    }

    /// Whether the results are the most played stations rather than a search.
    public var isShowingPopular: Bool { query.isEmpty }

    private var query: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Searches for the current text and field. Call it whenever either
    /// changes; it waits for typing to pause, so most calls end early.
    public func update() async {
        generation += 1
        let mine = generation
        let query = query
        let field = field
        if query.isEmpty, let popular {
            state = .loaded(popular)
            return
        }
        if !query.isEmpty {
            try? await Task.sleep(for: pause)
            guard mine == generation, !Task.isCancelled else { return }
        }
        state = .loading
        do {
            let found = query.isEmpty ? try await sources.popular() : try await sources.search(query, field)
            guard mine == generation, !Task.isCancelled else { return }
            if query.isEmpty { popular = found }
            state = .loaded(found)
        } catch {
            guard mine == generation, !Task.isCancelled else { return }
            state = .failed(Self.message(for: error))
        }
    }

    /// Tells Radio Browser a station found there was played. A failure
    /// doesn't matter to the user, so it's ignored.
    public func played(_ station: RadioBrowserStation) {
        let countPlay = sources.countPlay
        Task { try? await countPlay(station.id) }
    }

    static func message(for error: any Error) -> String {
        if error is URLError { return "Couldn't reach Radio Browser. Check your connection and try again." }
        return "Radio Browser's answer couldn't be read. Try again later."
    }
}
