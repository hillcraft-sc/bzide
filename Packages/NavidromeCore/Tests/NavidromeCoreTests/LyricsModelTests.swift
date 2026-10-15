import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct LyricsModelTests {
    private let song = Song(id: "so-1", title: "Morning Static", artist: "The Placeholders", duration: 200)
    private let synced = Lyrics(timed: [.init(start: 1, text: "Synced line")], songDuration: 200, source: .server)
    private let plain = Lyrics(plain: "Plain line", source: .server)
    private let onlineSynced = Lyrics(timed: [.init(start: 1, text: "Online synced")], songDuration: 200, source: .lrclib)
    private let onlinePlain = Lyrics(plain: "Online plain", source: .lrclib)

    /// Counts calls to each source.
    private actor Calls {
        var server = 0
        var online = 0
        func countServer() { server += 1 }
        func countOnline() { online += 1 }
    }

    private struct Unreachable: Error {}

    private func model(
        server: Lyrics?, online: LyricsModel.OnlineLyrics?, serverFails: Bool = false, onlineFails: Bool = false, calls: Calls = Calls()
    ) -> LyricsModel {
        LyricsModel(sources: .init(
            server: { _ in
                await calls.countServer()
                if serverFails { throw Unreachable() }
                return server
            },
            online: { _ in
                await calls.countOnline()
                if onlineFails { throw Unreachable() }
                return online
            }
        ))
    }

    @Test func theServersSyncedLyricsWinWithoutLookingOnline() async {
        let calls = Calls()
        let lyrics = model(server: synced, online: .lyrics(onlineSynced), calls: calls)
        await lyrics.load(song, onlineAllowed: true)
        #expect(lyrics.state == .loaded(synced))
        #expect(await calls.online == 0)
    }

    @Test func onlineSyncedLyricsBeatTheServersPlainOnes() async {
        let lyrics = model(server: plain, online: .lyrics(onlineSynced))
        await lyrics.load(song, onlineAllowed: true)
        #expect(lyrics.state == .loaded(onlineSynced))
    }

    @Test func onlineIsntAskedUnlessAllowed() async {
        let calls = Calls()
        let lyrics = model(server: plain, online: .lyrics(onlineSynced), calls: calls)
        await lyrics.load(song, onlineAllowed: false)
        #expect(lyrics.state == .loaded(plain))
        #expect(await calls.online == 0)
    }

    @Test func theServersPlainLyricsBeatOnlinePlainOnes() async {
        let lyrics = model(server: plain, online: .lyrics(onlinePlain))
        await lyrics.load(song, onlineAllowed: true)
        #expect(lyrics.state == .loaded(plain))
    }

    @Test func onlinePlainLyricsWhenTheServerHasNone() async {
        let lyrics = model(server: nil, online: .lyrics(onlinePlain))
        await lyrics.load(song, onlineAllowed: true)
        #expect(lyrics.state == .loaded(onlinePlain))
    }

    @Test func anInstrumental() async {
        let lyrics = model(server: nil, online: .instrumental)
        await lyrics.load(song, onlineAllowed: true)
        #expect(lyrics.state == .instrumental)
    }

    @Test func noLyricsAnywhere() async {
        let lyrics = model(server: nil, online: nil)
        await lyrics.load(song, onlineAllowed: true)
        #expect(lyrics.state == .none(note: "LRCLIB has no lyrics for this song either."))
    }

    @Test func noLyricsSaysWhyNothingWasFoundOnline() async {
        let turnedDown = model(server: nil, online: .notFound(.performance(candidate: ["live"], song: [])))
        await turnedDown.load(song, onlineAllowed: true)
        #expect(turnedDown.state == .none(note: LyricsMatching.explain(.performance(candidate: ["live"], song: []))))

        let notAllowed = model(server: nil, online: nil)
        await notAllowed.load(song, onlineAllowed: false)
        #expect(notAllowed.state == .none(note: LyricsModel.onlineOffNote))

        let unreachable = model(server: nil, online: nil, onlineFails: true)
        await unreachable.load(song, onlineAllowed: true)
        #expect(unreachable.state == .none(note: LyricsModel.onlineFailedNote))
    }

    @Test func anUnreachableServerIsAFailureUnlessOnlineAnswered() async {
        let offline = model(server: nil, online: nil, serverFails: true)
        await offline.load(song, onlineAllowed: false)
        guard case .failed = offline.state else {
            Issue.record("Expected a failure, got \(offline.state)")
            return
        }
        let answered = model(server: nil, online: nil, serverFails: true)
        await answered.load(song, onlineAllowed: true)
        #expect(answered.state == .none(note: "LRCLIB has no lyrics for this song either."))
    }

    @Test func radioHasNoLyrics() async {
        let station = Song(station: RadioStation(id: "st-1", name: "Station", streamURL: URL(string: "https://radio.example.test/stream")!), stream: URL(string: "https://radio.example.test/stream")!)
        let lyrics = model(server: synced, online: nil)
        await lyrics.load(station, onlineAllowed: true)
        #expect(lyrics.state == .radio)
    }

    @Test func foundLyricsAreKeptButFailuresAreRetried() async {
        let calls = Calls()
        let lyrics = model(server: synced, online: nil, calls: calls)
        await lyrics.load(song, onlineAllowed: true)
        await lyrics.load(song, onlineAllowed: true)
        #expect(await calls.server == 1)

        let failing = Calls()
        let offline = model(server: nil, online: nil, serverFails: true, calls: failing)
        await offline.load(song, onlineAllowed: false)
        await offline.load(song, onlineAllowed: false)
        #expect(await failing.server == 2)
    }

    @Test func aFailedLookupOnlineIsTriedAgain() async {
        let calls = Calls()
        let lyrics = model(server: nil, online: nil, onlineFails: true, calls: calls)
        await lyrics.load(song, onlineAllowed: true)
        #expect(lyrics.state == .none(note: LyricsModel.onlineFailedNote))
        await lyrics.load(song, onlineAllowed: true)
        #expect(await calls.online == 2)
    }

    @Test func aCanceledLoadShowsAndKeepsNothing() async {
        let calls = Calls()
        let gate = Gate()
        let lyrics = LyricsModel(sources: .init(
            server: { _ in nil },
            online: { _ in
                await calls.countOnline()
                await gate.wait()
                // What URLSession throws when its task is canceled.
                if Task.isCancelled { throw URLError(.cancelled) }
                return .lyrics(Lyrics(plain: "Online plain", source: .lrclib))
            }
        ))
        // The lyrics screen closes while LRCLIB is being searched.
        let closed = Task { await lyrics.load(song, onlineAllowed: true) }
        while lyrics.state != .loading { await Task.yield() }
        closed.cancel()
        await gate.open()
        await closed.value
        #expect(lyrics.state == .loading)
        // Reopened: asked again, not a remembered failure.
        await lyrics.load(song, onlineAllowed: true)
        #expect(lyrics.state == .loaded(Lyrics(plain: "Online plain", source: .lrclib)))
        #expect(await calls.online == 2)
    }

    @Test func reopeningWhileACanceledLoadIsStillRunningStillLoads() async {
        let gate = Gate()
        let answer = Lyrics(plain: "Online plain", source: .lrclib)
        let lyrics = LyricsModel(sources: .init(
            server: { _ in nil },
            online: { _ in
                await gate.wait()
                if Task.isCancelled { throw URLError(.cancelled) }
                return .lyrics(answer)
            }
        ))
        let closed = Task { await lyrics.load(song, onlineAllowed: true) }
        while lyrics.state != .loading { await Task.yield() }
        closed.cancel()
        // Reopened before the canceled search has ended.
        let reopened = Task { await lyrics.load(song, onlineAllowed: true) }
        await gate.open()
        await closed.value
        await reopened.value
        #expect(lyrics.state == .loaded(answer))
    }

    @Test func aSlowAnswerForAnEarlierSongIsDropped() async {
        let other = Song(id: "so-2", title: "Other Song")
        let otherLyrics = Lyrics(plain: "Other song's words", source: .server)
        let gate = Gate()
        let lyrics = LyricsModel(sources: .init(
            server: { song in
                if song.id == "so-1" {
                    await gate.wait()
                    return Lyrics(plain: "First song's words", source: .server)
                }
                return otherLyrics
            },
            online: { _ in nil }
        ))
        // The other song's lyrics are already known.
        await lyrics.load(other, onlineAllowed: false)
        // The first song starts loading slowly; the user skips to the other.
        let slow = Task { await lyrics.load(song, onlineAllowed: false) }
        while lyrics.state != .loading { await Task.yield() }
        await lyrics.load(other, onlineAllowed: false)
        await gate.open()
        await slow.value
        #expect(lyrics.state == .loaded(otherLyrics))
    }

    /// Holds a fake answer back until opened.
    private actor Gate {
        private var isOpen = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func open() {
            isOpen = true
            waiting.forEach { $0.resume() }
            waiting = []
        }
    }

    @Test func lrclibResultsBecomeLyrics() {
        let synced = LyricsModel.onlineLyrics(from: .init(synced: "[00:01.00]Hello\n[00:03.00]Again", plain: "Hello\nAgain", isInstrumental: false), songDuration: 10)
        guard case .lyrics(let lyrics) = synced else {
            Issue.record("Expected lyrics")
            return
        }
        #expect(lyrics.isSynced)
        #expect(lyrics.source == .lrclib)

        // "Synced" text without times falls back to the plain lyrics.
        let untimed = LyricsModel.onlineLyrics(from: .init(synced: "no times here", plain: "Hello", isInstrumental: false), songDuration: 10)
        #expect(untimed == .lyrics(Lyrics(plain: "Hello", source: .lrclib)))
        #expect(LyricsModel.onlineLyrics(from: .init(synced: nil, plain: nil, isInstrumental: true), songDuration: 10) == .instrumental)
        #expect(LyricsModel.onlineLyrics(from: .init(synced: nil, plain: nil, isInstrumental: false), songDuration: 10) == nil)
    }

    @Test func lookingOnlineIsOffByDefault() throws {
        #expect(StreamingSettings().findLyricsOnline == false)
        let older = try JSONDecoder().decode(StreamingSettings.self, from: Data(#"{"wifiQuality":0,"cellularQuality":192}"#.utf8))
        #expect(older.findLyricsOnline == false)
    }
}
