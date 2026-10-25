import Foundation
import Testing
@testable import NavidromeCore

struct BackgroundFileWriterTests {
    private let file = URL.temporaryDirectory.appending(path: "Writer-\(UUID().uuidString).json")

    private func onDisk() throws -> [Int] {
        try JSONDecoder().decode([Int].self, from: Data(contentsOf: file))
    }

    @Test func theLatestSaveEndsUpOnDisk() throws {
        let writer = BackgroundFileWriter<[Int]>(fileURL: file)
        for count in 1...50 { writer.save(Array(0..<count)) }
        writer.drain()
        #expect(try onDisk() == Array(0..<50))
        #expect(writer.unwritten == nil)
    }

    @Test func drainingAllWaitsForEveryWriter() throws {
        let other = URL.temporaryDirectory.appending(path: "Writer-\(UUID().uuidString).json")
        let first = BackgroundFileWriter<[Int]>(fileURL: file)
        let second = BackgroundFileWriter<[Int]>(fileURL: other)
        first.save([1])
        second.save([2])
        FileWriters.drainAll()
        #expect(try onDisk() == [1])
        #expect(try JSONDecoder().decode([Int].self, from: Data(contentsOf: other)) == [2])
    }

    @Test func aQueueSavedIsReadBackAtOnceAndAfterARelaunch() throws {
        let store = FileQueueStore(fileURL: file)
        let snapshot = QueueSnapshot(queue: PlaybackQueue(songs: [Song(id: "so-1", title: "Dawn")]), position: 12)
        try store.save(snapshot)
        // Before it's on disk too.
        #expect(try store.load() == snapshot)
        FileWriters.drainAll()
        #expect(try FileQueueStore(fileURL: file).load() == snapshot)
    }
}
