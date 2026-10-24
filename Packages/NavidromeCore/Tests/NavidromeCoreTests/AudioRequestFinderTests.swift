import Foundation
import Synchronization
import Testing
@testable import NavidromeCore

/// Siri's "play … in Bzide" must get a useful answer quickly, or Siri plays
/// Apple Music instead (Gitea #34).
struct AudioRequestFinderTests {
    /// A server held in memory; `searchDelay` makes it slow.
    final class Server: Sendable {
        struct State {
            var result = SearchResult(artists: [], albums: [], songs: [])
            var playlists: [Playlist] = []
            var current: Song?
            var playlistFetches = 0
        }

        let state = Mutex(State())
        let searchDelay: Duration?

        init(searchDelay: Duration? = nil) {
            self.searchDelay = searchDelay
        }

        var sources: AudioRequestFinder.Sources {
            AudioRequestFinder.Sources(
                search: { _ async throws(SubsonicError) in
                    if let delay = self.searchDelay {
                        do { try await Task.sleep(for: delay) } catch { throw .network(.cancelled) }
                    }
                    return self.state.withLock { $0.result }
                },
                playlists: { () async throws(SubsonicError) in
                    self.state.withLock { state in
                        state.playlistFetches += 1
                        return state.playlists
                    }
                },
                current: { self.state.withLock { $0.current } }
            )
        }
    }

    @Test func anExactNameComesFirst() async {
        let server = Server()
        server.state.withLock {
            $0.result = SearchResult(
                artists: [Artist(id: "ar-1", name: "Creed")],
                albums: [Album(id: "al-1", name: "Creed Greatest Hits")],
                songs: [Song(id: "so-1", title: "My Own Prison", artist: "Creed")]
            )
        }
        let matches = await AudioRequestFinder(sources: server.sources).find("creed")
        #expect(matches.first == .artist(Artist(id: "ar-1", name: "Creed")))
        #expect(matches.count == 3)
    }

    @Test func playlistsAreMatchedByName() async {
        let server = Server()
        server.state.withLock { $0.playlists = [Playlist(id: "pl-1", name: "Road Trip"), Playlist(id: "pl-2", name: "Focus")] }
        let matches = await AudioRequestFinder(sources: server.sources).find("Road Trip")
        #expect(matches == [.playlist(Playlist(id: "pl-1", name: "Road Trip"))])
    }

    @Test func nothingNamedResumesTheQueue() async {
        let server = Server()
        let song = Song(id: "so-9", title: "Dawn")
        server.state.withLock { $0.current = song }
        let finder = AudioRequestFinder(sources: server.sources)
        #expect(await finder.unspecified() == [.resume(song)])
        #expect(await finder.find("  ") == [.resume(song)])
    }

    @Test func nothingNamedAndNothingQueuedStartsARandomMix() async {
        let finder = AudioRequestFinder(sources: Server().sources)
        #expect(await finder.unspecified() == [.randomMix])
    }

    @Test func theAppsNameIsNotMusicToSearchFor() {
        // Siri heard "Bee-zide" as "Bzside" and searched for it.
        #expect(AudioRequestFinder.whatToPlay(in: "Bzside") == "")
        #expect(AudioRequestFinder.whatToPlay(in: "music in Bzside") == "")
        #expect(AudioRequestFinder.whatToPlay(in: "Music Bzside") == "")
        #expect(AudioRequestFinder.whatToPlay(in: "my music on B-Side") == "")
        #expect(AudioRequestFinder.whatToPlay(in: "Creed in Bzide") == "Creed")
        #expect(AudioRequestFinder.whatToPlay(in: "bee zide Kind of Blue") == "Kind of Blue")
    }

    @Test func genericWordsMeanPlayMusic() {
        for words in ["music", "My Music", "some music", "songs", "something", ""] {
            #expect(AudioRequestFinder.whatToPlay(in: words) == "", "\(words)")
        }
    }

    @Test func realSearchesAreLeftAlone() {
        #expect(AudioRequestFinder.whatToPlay(in: "Creed") == "Creed")
        #expect(AudioRequestFinder.whatToPlay(in: "Music for Airports") == "Music for Airports")
        #expect(AudioRequestFinder.whatToPlay(in: "B-Sides and Rarities") == "B-Sides and Rarities")
    }

    @Test func playMusicInTheMisheardAppResumes() async {
        let server = Server()
        let song = Song(id: "so-9", title: "Dawn")
        server.state.withLock { $0.current = song }
        #expect(await AudioRequestFinder(sources: server.sources).find("music in Bzside") == [.resume(song)])
    }

    @Test func randomMixCanBeAskedForByName() async {
        let finder = AudioRequestFinder(sources: Server().sources)
        #expect(await finder.find("random mix") == [.randomMix])
    }

    @Test func aSlowServerStillGetsAnAnswerInTime() async {
        let server = Server(searchDelay: .seconds(30))
        server.state.withLock {
            $0.result = SearchResult(artists: [Artist(id: "ar-1", name: "Creed")], albums: [], songs: [])
            $0.playlists = [Playlist(id: "pl-1", name: "Creed Mix")]
        }
        let started = ContinuousClock.now
        let matches = await AudioRequestFinder(sources: server.sources, deadline: .milliseconds(200)).find("Creed")
        #expect(ContinuousClock.now - started < .seconds(5))
        // The search didn't make it; the playlists did.
        #expect(matches == [.playlist(Playlist(id: "pl-1", name: "Creed Mix"))])
    }

    @Test func playlistsAreKeptForAWhile() async {
        let server = Server()
        server.state.withLock { $0.playlists = [Playlist(id: "pl-1", name: "Focus")] }
        let clock = Mutex(Date(timeIntervalSince1970: 0))
        let finder = AudioRequestFinder(sources: server.sources, playlistsFreshFor: 600, now: { clock.withLock { $0 } })
        _ = await finder.find("Focus")
        _ = await finder.find("Focus")
        #expect(server.state.withLock { $0.playlistFetches } == 1)
        clock.withLock { $0 += 601 }
        _ = await finder.find("Focus")
        #expect(server.state.withLock { $0.playlistFetches } == 2)
    }
}
