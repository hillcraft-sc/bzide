import Foundation
import Observation
import os

/// Downloads albums and playlists for offline playback and keeps track of them.
///
/// Each song is stored once, however many downloaded albums or playlists contain
/// it, and deleted only when none of them does any more. A few songs download at
/// a time; the rest wait their turn in the order they were added.
@MainActor
@Observable
public final class DownloadManager: DownloadedTrackLookup {
    public private(set) var collections: [DownloadCollection] = []

    private var files: [String: StoredFile] = [:]
    /// Running downloads and their progress.
    private var active: [String: Double?] = [:]
    /// Songs whose last attempt failed. Not saved: after a relaunch they're tried again.
    private var failures: [String: String] = [:]

    @ObservationIgnored private let transport: any DownloadTransport
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let downloadURL: (String) throws -> URL
    @ObservationIgnored private let allowsCellular: () -> Bool
    @ObservationIgnored private let artwork: (any ArtworkPinning)?

    static let maxConcurrent = 3
    nonisolated static let directoryName = "Downloads"
    private static let logger = Logger(subsystem: "MusicApp", category: "Downloads")

    /// `directory` holds the index and the song files. Call `resume()` once after
    /// creating, to pick up downloads from the last run.
    public init(
        directory: URL,
        transport: any DownloadTransport,
        downloadURL: @escaping (String) throws -> URL,
        allowsCellular: @escaping () -> Bool,
        artwork: (any ArtworkPinning)? = nil
    ) {
        self.directory = directory
        self.transport = transport
        self.downloadURL = downloadURL
        self.allowsCellular = allowsCellular
        self.artwork = artwork
        let index = Self.loadIndex(from: directory)
        collections = index.collections
        files = index.files
        transport.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: - Queries

    public func localFile(forSongID songID: String) -> URL? {
        guard let stored = files[songID] else { return nil }
        let url = filesDirectory.appending(path: stored.fileName)
        // A file removed behind our back (or by a restore) must fall back to streaming.
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    public func state(ofSong songID: String) -> SongDownloadState {
        if files[songID] != nil { return .done }
        if let progress = active[songID] { return .downloading(progress: progress) }
        if let message = failures[songID] { return .failed(message) }
        return isWanted(songID) ? .waiting : .notDownloaded
    }

    /// Newest download first, filtered by `DownloadCollection.matches(_:)`.
    public func collections(matching query: String) -> [DownloadCollection] {
        collections.filter { $0.matches(query) }.sorted { $0.addedAt > $1.addedAt }
    }

    public func collection(id: String) -> DownloadCollection? {
        collections.first { $0.id == id }
    }

    public func status(of collection: DownloadCollection) -> CollectionDownloadStatus {
        var status = CollectionDownloadStatus(songCount: collection.songs.count, doneCount: 0, failedCount: 0, progress: 0)
        guard !collection.songs.isEmpty else { return status }
        var progressSum = 0.0
        for song in collection.songs {
            switch state(ofSong: song.id) {
            case .done:
                status.doneCount += 1
                progressSum += 1
            case .downloading(let progress):
                progressSum += progress ?? 0
            case .failed:
                status.failedCount += 1
            case .waiting, .notDownloaded:
                break
            }
        }
        status.progress = progressSum / Double(collection.songs.count)
        return status
    }

    /// Every song whose file is on the device, once each, however many
    /// downloads contain it.
    public func downloadedSongs() -> [Song] {
        var seen = Set<String>()
        var songs: [Song] = []
        for collection in collections {
            for song in collection.songs where seen.insert(song.id).inserted && localFile(forSongID: song.id) != nil {
                songs.append(song)
            }
        }
        return songs
    }

    /// Bytes used by downloaded songs.
    public var totalBytes: Int64 {
        files.values.reduce(0) { $0 + $1.bytes }
    }

    // MARK: - Commands

    /// Downloads an album or playlist. Downloading one that's already there
    /// updates its song list (a playlist may have changed) and fetches what's new.
    public func download(_ collection: DownloadCollection) {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            var updated = collection
            updated.addedAt = collections[index].addedAt
            collections[index] = updated
            deleteUnusedFiles()
        } else {
            collections.append(collection)
        }
        collectionsChanged()
        startWaitingDownloads()
    }

    public func remove(collectionID: String) {
        collections.removeAll { $0.id == collectionID }
        deleteUnusedFiles()
        collectionsChanged()
        startWaitingDownloads()
    }

    public func removeAll() {
        collections = []
        deleteUnusedFiles()
        collectionsChanged()
    }

    /// Tries the failed songs of a collection again.
    public func retryFailed(in collection: DownloadCollection) {
        for song in collection.songs {
            failures[song.id] = nil
        }
        startWaitingDownloads()
    }

    /// Reconnects with downloads the system kept running while the app was gone,
    /// then starts whatever is still waiting.
    public func resume() async {
        for songID in await transport.activeSongIDs() where active[songID] == nil {
            if isWanted(songID), files[songID] == nil {
                active[songID] = .some(nil)
            } else {
                transport.cancel(songID: songID)
            }
        }
        // Covers that failed to fetch last time are tried again.
        artwork?.keepOffline(coverArtIDs: wantedCoverArtIDs())
        startWaitingDownloads()
    }

    // MARK: - Downloading

    private func startWaitingDownloads() {
        for songID in waitingSongIDs() {
            guard active.count < Self.maxConcurrent else { return }
            do {
                let url = try downloadURL(songID)
                active[songID] = .some(nil)
                transport.start(songID: songID, from: url, allowsCellular: allowsCellular())
            } catch {
                failures[songID] = error.localizedDescription
            }
        }
    }

    /// In the order the user asked for them: oldest download first, album order within.
    private func waitingSongIDs() -> [String] {
        var seen = Set<String>()
        var waiting: [String] = []
        for collection in collections.sorted(by: { $0.addedAt < $1.addedAt }) {
            for song in collection.songs where seen.insert(song.id).inserted {
                if files[song.id] == nil, active[song.id] == nil, failures[song.id] == nil {
                    waiting.append(song.id)
                }
            }
        }
        return waiting
    }

    private func handle(_ event: DownloadEvent) {
        switch event {
        case .progress(let songID, let fraction):
            guard let current = active[songID] else { return }
            // iOS reports progress many times a second; redraw only on visible change.
            if let current, let fraction, abs(fraction - current) < 0.01 { return }
            active[songID] = .some(fraction)
        case .finished(let songID, let file, let fileExtension):
            active[songID] = nil
            store(file, for: songID, fileExtension: fileExtension)
            startWaitingDownloads()
        case .failed(let songID, let message):
            guard active.removeValue(forKey: songID) != nil else { return }
            Self.logger.error("Download failed: \(message, privacy: .public)")
            failures[songID] = message
            startWaitingDownloads()
        }
    }

    private func store(_ file: URL, for songID: String, fileExtension: String?) {
        let fileManager = FileManager.default
        // Removed while it was downloading: nothing wants it now.
        guard isWanted(songID) else {
            try? fileManager.removeItem(at: file)
            return
        }
        let suffix = song(songID)?.suffix ?? fileExtension ?? "audio"
        let fileName = "\(songID).\(suffix)"
        let destination = filesDirectory.appending(path: fileName)
        do {
            try fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: file, to: destination)
            let size = try fileManager.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? Int64
            files[songID] = StoredFile(fileName: fileName, bytes: size ?? 0)
            failures[songID] = nil
            saveIndex()
        } catch {
            try? fileManager.removeItem(at: file)
            failures[songID] = "Couldn't save the file: \(error.localizedDescription)"
        }
    }

    // MARK: - Housekeeping

    private func collectionsChanged() {
        saveIndex()
        artwork?.keepOffline(coverArtIDs: wantedCoverArtIDs())
    }

    /// The album or playlist cover and every song's cover, which can differ
    /// (compilations, playlists).
    private func wantedCoverArtIDs() -> Set<String> {
        var ids = Set<String>()
        for collection in collections {
            if let id = collection.coverArtID { ids.insert(id) }
            for song in collection.songs {
                if let id = song.coverArtID { ids.insert(id) }
            }
        }
        return ids
    }

    private func isWanted(_ songID: String) -> Bool {
        collections.contains { $0.songs.contains { $0.id == songID } }
    }

    private func song(_ songID: String) -> Song? {
        for collection in collections {
            if let song = collection.songs.first(where: { $0.id == songID }) { return song }
        }
        return nil
    }

    /// Deletes files and stops downloads that no collection needs any more.
    private func deleteUnusedFiles() {
        for songID in files.keys where !isWanted(songID) {
            if let stored = files.removeValue(forKey: songID) {
                try? FileManager.default.removeItem(at: filesDirectory.appending(path: stored.fileName))
            }
        }
        for songID in active.keys where !isWanted(songID) {
            active[songID] = nil
            transport.cancel(songID: songID)
        }
        for songID in failures.keys where !isWanted(songID) {
            failures[songID] = nil
        }
    }

    // MARK: - Index

    private var filesDirectory: URL { directory.appending(path: "Files") }
    private static func indexURL(in directory: URL) -> URL { directory.appending(path: "index.json") }

    private static func loadIndex(from directory: URL) -> DownloadIndex {
        let url = indexURL(in: directory)
        guard let data = try? Data(contentsOf: url) else { return DownloadIndex() }
        do {
            return try JSONDecoder().decode(DownloadIndex.self, from: data)
        } catch {
            // The files are still there, but without the index nothing points at them.
            logger.error("Download index unreadable, starting empty: \(String(describing: error), privacy: .public)")
            return DownloadIndex()
        }
    }

    private func saveIndex() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(DownloadIndex(collections: collections, files: files))
            try data.write(to: Self.indexURL(in: directory), options: .atomic)
        } catch {
            Self.logger.error("Couldn't save the download index: \(String(describing: error), privacy: .public)")
        }
    }

    /// `Application Support/Downloads`, excluded from iCloud backup: it can be
    /// downloaded again, and may be large.
    public static func applicationSupportDirectory() throws -> URL {
        var directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory
    }
}
