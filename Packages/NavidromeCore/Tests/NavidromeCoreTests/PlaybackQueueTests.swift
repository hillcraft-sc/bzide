import Foundation
import Testing
@testable import NavidromeCore

struct PlaybackQueueTests {
    private let songs = (1...4).map { Song(id: "so-\($0)", title: "Song \($0)") }

    @Test func emptyQueueHasNothingCurrent() {
        var queue = PlaybackQueue()
        #expect(queue.isEmpty)
        #expect(queue.current == nil)
        #expect(queue.upNext.isEmpty)
        let advanced = queue.advance()
        #expect(!advanced)
        let wentBack = queue.goBack()
        #expect(!wentBack)
    }

    @Test func startsAtRequestedIndexClampedIntoRange() {
        #expect(PlaybackQueue(songs: songs, startIndex: 2).current?.song.id == "so-3")
        #expect(PlaybackQueue(songs: songs, startIndex: 99).current?.song.id == "so-4")
        #expect(PlaybackQueue(songs: songs, startIndex: -1).current?.song.id == "so-1")
        #expect(PlaybackQueue(songs: [], startIndex: 3).current == nil)
    }

    @Test func advancesUntilTheEndThenStays() {
        var queue = PlaybackQueue(songs: songs, startIndex: 2)
        #expect(queue.upNext.map(\.song.id) == ["so-4"])
        let advancedToLast = queue.advance()
        #expect(advancedToLast)
        #expect(queue.current?.song.id == "so-4")
        #expect(!queue.hasNext)
        let advancedPastEnd = queue.advance()
        #expect(!advancedPastEnd)
        #expect(queue.current?.song.id == "so-4")
    }

    @Test func goesBackUntilTheStartThenStays() {
        var queue = PlaybackQueue(songs: songs, startIndex: 1)
        let wentBack = queue.goBack()
        #expect(wentBack)
        #expect(queue.current?.song.id == "so-1")
        let wentBackPastStart = queue.goBack()
        #expect(!wentBackPastStart)
        #expect(queue.current?.song.id == "so-1")
    }

    @Test func jumpsByEntryNotBySong() {
        // The same song twice: jumping must land on the exact entry chosen.
        var queue = PlaybackQueue(songs: [songs[0], songs[1], songs[0]])
        let secondCopy = queue.entries[2]
        let jumped = queue.jump(to: secondCopy.id)
        #expect(jumped)
        #expect(queue.currentIndex == 2)
        let jumpedToUnknown = queue.jump(to: UUID())
        #expect(!jumpedToUnknown)
        #expect(queue.currentIndex == 2)
    }

    @Test func appendingToAnEmptyQueueMakesFirstSongCurrent() {
        var queue = PlaybackQueue()
        queue.append([songs[0], songs[1]])
        #expect(queue.current?.song.id == "so-1")
        queue.append([songs[2]])
        #expect(queue.current?.song.id == "so-1")
        #expect(queue.upNext.map(\.song.id) == ["so-2", "so-3"])
    }

    @Test func previousRestartsAfterThreeSeconds() {
        #expect(PreviousAction.decide(elapsed: 3.5, hasPrevious: true) == .restartCurrent)
        #expect(PreviousAction.decide(elapsed: 3.0, hasPrevious: true) == .goToPrevious)
        #expect(PreviousAction.decide(elapsed: 0.5, hasPrevious: true) == .goToPrevious)
        // On the first track there is nothing to go back to.
        #expect(PreviousAction.decide(elapsed: 0.5, hasPrevious: false) == .restartCurrent)
    }
}

struct QueuePersistenceTests {
    private let song = Song(
        id: "so-1", title: "Dawn", album: "First Light", albumID: "al-1", artist: "Aurora Lines",
        artistID: "ar-1", track: 1, discNumber: 1, year: 2019, genre: "Ambient", coverArtID: "mf-so-1",
        duration: 201, bitRate: 900, suffix: "flac", contentType: "audio/flac", isStarred: true, userRating: 3
    )

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "queue-\(UUID().uuidString).json")
    }

    @Test func songSurvivesEncodeDecodeWithEveryField() throws {
        let unstarred = Song(id: "so-2", title: "Noon")
        for original in [song, unstarred] {
            let decoded = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(original))
            #expect(decoded == original)
        }
    }

    @Test func fileStoreRoundTripsQueueAndPosition() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = FileQueueStore(fileURL: file)
        #expect(try store.load() == nil)

        var queue = PlaybackQueue(songs: [song, Song(id: "so-2", title: "Noon")])
        queue.advance()
        let snapshot = QueueSnapshot(queue: queue, position: 42.5)
        try store.save(snapshot)
        #expect(try store.load() == snapshot)
    }

    @Test func corruptFileIsReportedNotCrashed() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{not json".utf8).write(to: file)
        #expect(throws: QueueStoreError.unreadable) {
            try FileQueueStore(fileURL: file).load()
        }
    }

    @Test func outOfRangeSavedIndexIsClamped() throws {
        let entry = QueueEntry(song: song)
        let json = """
        {"entries":[\(String(decoding: try JSONEncoder().encode(entry), as: UTF8.self))],"currentIndex":7}
        """
        let queue = try JSONDecoder().decode(PlaybackQueue.self, from: Data(json.utf8))
        #expect(queue.currentIndex == 0)
        #expect(queue.current == entry)
    }
}
