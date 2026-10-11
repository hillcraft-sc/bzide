import Foundation
import Testing
@testable import NavidromeCore

/// The response checks run on every finished download; the session itself needs a device.
struct DownloadResponseTests {
    private let root = URL.temporaryDirectory.appending(path: "DownloadResponseTests-\(UUID().uuidString)")
    private let url = URL(string: "https://music.example.test/rest/download?id=so-1")!

    private func downloadedFile() throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: UUID().uuidString)
        try Data("bytes".utf8).write(to: file)
        return file
    }

    private func response(status: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    @Test func audioIsKeptWithTheServersExtension() throws {
        let file = try downloadedFile()
        let event = BackgroundDownloadTransport.takeFile(
            at: file,
            response: response(status: 200, headers: ["Content-Type": "audio/flac", "Content-Disposition": "attachment; filename=\"Dawn.flac\""]),
            songID: "so-1",
            stagingDirectory: root.appending(path: "staging")
        )
        guard case .finished("so-1", let staged, let fileExtension) = event else {
            Issue.record("Expected finished, got \(event)")
            return
        }
        #expect(fileExtension == "flac")
        #expect(FileManager.default.fileExists(atPath: staged.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test func aSubsonicErrorBodyIsNotSavedAsASong() throws {
        let event = BackgroundDownloadTransport.takeFile(
            at: try downloadedFile(),
            response: response(status: 200, headers: ["Content-Type": "application/json"]),
            songID: "so-1",
            stagingDirectory: root.appending(path: "staging")
        )
        #expect(event == .failed(songID: "so-1", message: "The server refused the download."))
    }

    @Test func anHTTPErrorFails() throws {
        let event = BackgroundDownloadTransport.takeFile(
            at: try downloadedFile(),
            response: response(status: 404, headers: [:]),
            songID: "so-1",
            stagingDirectory: root.appending(path: "staging")
        )
        #expect(event == .failed(songID: "so-1", message: "The server returned HTTP 404."))
    }
}
