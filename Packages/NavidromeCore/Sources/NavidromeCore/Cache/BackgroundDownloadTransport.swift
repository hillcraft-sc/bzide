import Foundation
import Synchronization

/// `DownloadTransport` backed by a background `URLSession`, so downloads carry on
/// while the app is suspended or terminated. Create one at launch and keep it for
/// the app's lifetime; iOS reconnects it to running downloads by its identifier.
///
/// The download URLs carry an auth token and are handed to iOS's download
/// service; Subsonic has no other way to authenticate a download.
@MainActor
public final class BackgroundDownloadTransport: NSObject, DownloadTransport {
    public var onEvent: (@MainActor (DownloadEvent) -> Void)?

    public static let sessionIdentifier = "MusicApp.downloads"

    /// iOS hands the app a completion handler when it wakes it for finished
    /// background downloads, before the transport may exist. It's parked here
    /// and called once the session has delivered everything.
    private nonisolated static let pendingEventsCompletion = Mutex<(@Sendable () -> Void)?>(nil)

    /// Where finished files go before the manager takes them; iOS deletes its
    /// own temporary file as soon as the delegate call returns.
    private let stagingDirectory: URL
    /// Made on first use, which `init` does at once: the session's delegate
    /// is `self`, which can't be used before `super.init()`.
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        // Download URLs carry the login token: nothing kept beyond the files.
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private var tasks: [String: URLSessionDownloadTask] = [:]

    public init(stagingDirectory: URL) {
        self.stagingDirectory = stagingDirectory
        super.init()
        // Now, so iOS reconnects running downloads at launch.
        _ = session
    }

    /// Call from `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    public nonisolated static func handleBackgroundEvents(completion: @escaping @Sendable () -> Void) {
        pendingEventsCompletion.withLock { $0 = completion }
    }

    public func start(songID: String, from url: URL, allowsCellular: Bool) {
        var request = URLRequest(url: url)
        request.allowsCellularAccess = allowsCellular
        let task = session.downloadTask(with: request)
        task.taskDescription = songID
        tasks[songID] = task
        task.resume()
    }

    public func cancel(songID: String) {
        tasks.removeValue(forKey: songID)?.cancel()
    }

    public func activeSongIDs() async -> Set<String> {
        var ids = Set<String>()
        for case let task as URLSessionDownloadTask in await session.allTasks where task.state == .running || task.state == .suspended {
            guard let songID = task.taskDescription else { continue }
            tasks[songID] = task
            ids.insert(songID)
        }
        return ids
    }

    private func deliver(_ event: DownloadEvent) {
        switch event {
        case .finished(let songID, _, _), .failed(let songID, _):
            tasks[songID] = nil
        case .progress:
            break
        }
        onEvent?(event)
    }

    /// Checks the response and moves the file out of iOS's temporary location.
    /// Subsonic reports errors as HTTP 200 with a JSON or XML body, so the
    /// content type matters as much as the status.
    nonisolated static func takeFile(at location: URL, response: URLResponse?, songID: String, stagingDirectory: URL) -> DownloadEvent {
        guard let http = response as? HTTPURLResponse else {
            return .failed(songID: songID, message: "No response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failed(songID: songID, message: "The server returned HTTP \(http.statusCode).")
        }
        let mimeType = http.mimeType ?? ""
        guard !mimeType.contains("json"), !mimeType.contains("xml") else {
            return .failed(songID: songID, message: "The server refused the download.")
        }
        let staged = stagingDirectory.appending(path: UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: staged)
        } catch {
            return .failed(songID: songID, message: "Couldn't save the file: \(error.localizedDescription)")
        }
        let fileExtension = http.suggestedFilename.map { ($0 as NSString).pathExtension }.flatMap { $0.isEmpty ? nil : $0 }
        return .finished(songID: songID, file: staged, fileExtension: fileExtension)
    }
}

extension BackgroundDownloadTransport: URLSessionDownloadDelegate {
    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let songID = downloadTask.taskDescription else { return }
        // Must happen before returning: iOS deletes `location` afterwards.
        let event = Self.takeFile(at: location, response: downloadTask.response, songID: songID, stagingDirectory: stagingDirectory)
        Task { @MainActor [weak self] in self?.deliver(event) }
    }

    public nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let songID = downloadTask.taskDescription else { return }
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil
        Task { @MainActor [weak self] in self?.deliver(.progress(songID: songID, fraction: fraction)) }
    }

    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // Success was already reported when the file arrived.
        guard let error, let songID = task.taskDescription else { return }
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.deliver(.failed(songID: songID, message: message)) }
    }

    public nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = Self.pendingEventsCompletion.withLock { pending in
            defer { pending = nil }
            return pending
        }
        // iOS expects this on the main thread.
        Task { @MainActor in completion?() }
    }
}
