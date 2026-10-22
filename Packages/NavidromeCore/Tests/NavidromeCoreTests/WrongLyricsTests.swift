import Foundation
import Testing
@testable import NavidromeCore

/// Gitea #6: "Wrong lyrics?" tries LRCLIB's next match, remembered per song.
struct LRCLIBMatchesTests {
    private static func record(_ id: Int, duration: Int = 200, synced: String) -> String {
        #"{"id":\#(id),"trackName":"Morning Static","artistName":"The Placeholders","duration":\#(duration),"syncedLyrics":"\#(synced)"}"#
    }

    @Test func theSearchsMatchesBestFirstWithoutRepeats() async throws {
        let search = "[" + [
            Self.record(1, synced: "[00:01.00] Wake up"),
            Self.record(1, synced: "[00:01.00] Wake up"),
            // The same words at other times: not really another version.
            Self.record(2, duration: 201, synced: "[00:03.00] Wake  UP"),
            Self.record(3, duration: 202, synced: "[00:02.00] Wake up, it's the radio edit"),
            Self.record(4, duration: 200, synced: "[00:01.50] Wake up, album version"),
            // Far too long: turned down.
            Self.record(5, duration: 400, synced: "[00:01.00] Wake up live"),
        ].joined(separator: ",") + "]"
        let transport = FakeTransport(.json(search))
        let matches = try await LRCLIBClient(transport: transport).matches(title: "Morning Static", artist: "The Placeholders", album: nil, duration: 200)
        #expect(matches.map(\.id) == [1, 4, 3])
        // Only the search: no exact lookups, which can be slow.
        let paths = await transport.requests.compactMap { $0.url?.path }
        #expect(paths == ["/api/search"])
    }

    @Test func aFailedSearchIsTriedOnceMore() async throws {
        let transport = FakeTransport(.json("{}", status: 502), .json("[" + Self.record(1, synced: "[00:01.00] Wake up") + "]"))
        let matches = try await LRCLIBClient(transport: transport).matches(title: "Morning Static", artist: "The Placeholders", album: nil, duration: 200)
        #expect(matches.map(\.id) == [1])
        #expect(await transport.requests.count == 2)
    }

    @Test func twoFailuresAreAFailure() async {
        let transport = FakeTransport(.failure(.timedOut), .failure(.timedOut))
        await #expect(throws: URLError.self) {
            try await LRCLIBClient(transport: transport).matches(title: "Morning Static", artist: "The Placeholders", album: nil, duration: 200)
        }
    }
}

struct LyricsChoicesTests {
    private func defaults() -> UserDefaults {
        let name = "LyricsChoicesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func choicesAreKeptAndForgotten() {
        let store = defaults()
        let choices = LyricsChoices(defaults: store)
        choices.set(.lrclib(id: 4), for: "so-1")
        choices.set(.turnedDown, for: "so-2")
        let again = LyricsChoices(defaults: store)
        #expect(again.choice(for: "so-1") == .lrclib(id: 4))
        #expect(again.choice(for: "so-2") == .turnedDown)
        again.set(nil, for: "so-1")
        #expect(LyricsChoices(defaults: store).choice(for: "so-1") == nil)
    }

    @Test func theOldestGoFirst() {
        let choices = LyricsChoices(defaults: defaults())
        for index in 0...LyricsChoices.maximumSongs {
            choices.set(.lrclib(id: index), for: "so-\(index)")
        }
        #expect(choices.choice(for: "so-0") == nil)
        #expect(choices.choice(for: "so-1") == .lrclib(id: 1))
    }

    @Test func restoringTheDefaultsKeepsThem() {
        #expect(AccountSettings.keptByRestore.contains(LyricsChoices.key))
    }
}

@MainActor
struct WrongLyricsModelTests {
    private let song = Song(id: "so-1", title: "Morning Static", artist: "The Placeholders", duration: 200)

    private static func online(_ id: Int, _ text: String) -> Lyrics {
        var lyrics = Lyrics(timed: [.init(start: 1, text: text)], songDuration: 200, source: .lrclib)
        lyrics.lrclibID = id
        return lyrics
    }

    private let first = online(1, "Best match")
    private let second = online(4, "Next match")
    private let third = online(3, "Last match")

    private final class Box: @unchecked Sendable {
        var matchesFail = false
        var entries: [Int: Lyrics] = [:]
        var server: Lyrics?
    }

    private func model(_ box: Box = Box(), choices: LyricsChoices) -> LyricsModel {
        let first = first, all = [first, second, third]
        return LyricsModel(sources: .init(
            server: { _ in box.server },
            online: { _ in .lyrics(first) },
            onlineEntry: { _, id in box.entries[id] },
            onlineMatches: { _ in
                if box.matchesFail { throw URLError(.notConnectedToInternet) }
                return all
            }
        ), choices: choices)
    }

    private func choices() -> LyricsChoices {
        let name = "WrongLyrics-\(UUID().uuidString)"
        return LyricsChoices(defaults: UserDefaults(suiteName: name) ?? .standard)
    }

    @Test func eachTryShowsTheNextMatchAndRemembersIt() async {
        let saved = choices()
        let box = Box()
        let lyrics = model(box, choices: saved)
        await lyrics.load(song, onlineAllowed: true)
        #expect(lyrics.state == .loaded(first))

        #expect(await lyrics.tryAnother() == .shown)
        #expect(lyrics.state == .loaded(second))
        #expect(saved.choice(for: song.id) == .lrclib(id: 4))
        #expect(await lyrics.tryAnother() == .shown)
        #expect(lyrics.state == .loaded(third))
        // The end of the list.
        #expect(await lyrics.tryAnother() == .noMore)
        #expect(lyrics.state == .loaded(third))

        // Next time, the choice is fetched by its id.
        box.entries[3] = third
        let later = model(box, choices: saved)
        await later.load(song, onlineAllowed: true)
        #expect(later.state == .loaded(third))
    }

    @Test func whatsShowingNotInTheListStartsFromTheTopButNeverRepeatsTheWords() async {
        let saved = choices()
        // Shown from an exact lookup: id 9, the same words as the list's first.
        let shown = Self.online(9, "Best match")
        let all = [first, second]
        let lyrics = LyricsModel(sources: .init(
            server: { _ in nil },
            online: { _ in .lyrics(shown) },
            onlineMatches: { _ in all }
        ), choices: saved)
        await lyrics.load(song, onlineAllowed: true)
        #expect(await lyrics.tryAnother() == .shown)
        #expect(lyrics.state == .loaded(second))
    }

    @Test func aChosenEntryThatCantBeFoundJustNowFallsBackToTheBestMatch() async {
        let saved = choices()
        saved.set(.lrclib(id: 4), for: song.id)
        let first = first
        let lyrics = LyricsModel(sources: .init(
            server: { _ in nil },
            online: { _ in .lyrics(first) },
            onlineEntry: { _, _ in throw URLError(.badServerResponse) }
        ), choices: saved)
        await lyrics.load(song, onlineAllowed: true)
        #expect(lyrics.state == .loaded(first))
        // The choice is kept for next time.
        #expect(saved.choice(for: song.id) == .lrclib(id: 4))
    }

    @Test func aChosenEntryGoneFromLRCLIBFallsBackToTheBestMatch() async {
        let saved = choices()
        saved.set(.lrclib(id: 99), for: song.id)
        let lyrics = model(choices: saved)
        await lyrics.load(song, onlineAllowed: true)
        #expect(lyrics.state == .loaded(first))
    }

    @Test func turningLRCLIBDownShowsTheServersOrNone() async {
        let saved = choices()
        let box = Box()
        let lyrics = model(box, choices: saved)
        await lyrics.load(song, onlineAllowed: true)
        await lyrics.turnDownOnline()
        #expect(saved.choice(for: song.id) == .turnedDown)
        #expect(lyrics.state == .none(note: LyricsModel.onlineTurnedDownNote))

        // With plain lyrics on the server, those.
        box.server = Lyrics(plain: "Server words", source: .server)
        let other = model(box, choices: saved)
        await other.load(song, onlineAllowed: true)
        #expect(other.state == .loaded(Lyrics(plain: "Server words", source: .server)))

        // And back.
        await lyrics.useBestMatch()
        #expect(saved.choice(for: song.id) == nil)
        #expect(lyrics.state == .loaded(first))
    }

    @Test func aFailedLookupChangesNothing() async {
        let saved = choices()
        let box = Box()
        box.matchesFail = true
        let lyrics = model(box, choices: saved)
        await lyrics.load(song, onlineAllowed: true)
        #expect(await lyrics.tryAnother() == .failed)
        #expect(lyrics.state == .loaded(first))
        #expect(saved.choice(for: song.id) == nil)
    }

    @Test func theServersLyricsAreNeverChanged() async {
        let saved = choices()
        let box = Box()
        box.server = Lyrics(timed: [.init(start: 1, text: "Server synced")], songDuration: 200, source: .server)
        let lyrics = model(box, choices: saved)
        await lyrics.load(song, onlineAllowed: true)
        #expect(await lyrics.tryAnother() == .noMore)
        #expect(saved.choice(for: song.id) == nil)
    }
}

@MainActor
struct WrongLyricsSettingTests {
    private let song = Song(id: "so-1", title: "Morning Static", artist: "The Placeholders", duration: 200)

    @Test func offByDefaultAndForOlderSettings() throws {
        #expect(StreamingSettings().wrongLyricsButton == false)
        let old = try JSONDecoder().decode(StreamingSettings.self, from: Data(#"{"findLyricsOnline":true}"#.utf8))
        #expect(old.wrongLyricsButton == false)
    }

    /// With the setting off, choices made before are ignored (and kept).
    @Test func choicesApplyOnlyWithTheSettingOn() async {
        let choices = LyricsChoices(defaults: UserDefaults(suiteName: "WrongLyricsSetting-\(UUID().uuidString)") ?? .standard)
        choices.set(.turnedDown, for: song.id)
        var best = Lyrics(plain: "Best match", source: .lrclib)
        best.lrclibID = 1
        let model = LyricsModel(sources: .init(server: { _ in nil }, online: { [best] _ in .lyrics(best) }), choices: choices)

        await model.load(song, onlineAllowed: true, usesChoices: false)
        #expect(model.state == .loaded(best))
        // No trying another without the setting.
        #expect(await model.tryAnother() == .noMore)
        #expect(choices.choice(for: song.id) == .turnedDown)

        await model.load(song, onlineAllowed: true, usesChoices: true)
        #expect(model.state == .none(note: LyricsModel.onlineTurnedDownNote))
    }
}
