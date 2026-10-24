import CoreTransferable
import NavidromeCore
import SwiftUI
import UniformTypeIdentifiers

/// What Settings > Backup does, from `AppModel`.
struct BackupActions {
    let make: (_ includingHistory: Bool) throws(BackupError) -> AccountBackup
    let isFromAnotherAccount: (AccountBackup) -> Bool
    let restore: (AccountBackup) throws(BackupError) -> Void
}

/// Settings > Backup (Gitea #38): Back Up Bzide Data saves one file through
/// the Files picker, wherever the user chooses; Restore from Backup reads one
/// back, after a confirmation, replacing this iPhone's data with it.
struct BackupSection: View {
    let actions: BackupActions

    @State private var includesHistory = true
    @State private var exporting: BackupFile?
    @State private var isImporting = false
    @State private var restoring: AccountBackup?
    @State private var message: String?

    var body: some View {
        Section {
            Toggle("Include Play History", isOn: $includesHistory)
            Button("Back Up Bzide Data", systemImage: "square.and.arrow.up", action: backUp)
            Button("Restore from Backup", systemImage: "arrow.counterclockwise") { isImporting = true }
        } header: {
            Text("Backup")
        } footer: {
            Text("Saves your settings, Wishlist, stations saved on this iPhone and, if you like, play history in one file, to keep wherever you choose (Bzide sends it nowhere), and to restore on a new iPhone or iPad. The file isn't encrypted. Never in it: your login, your server's address, downloads or the queue.")
        }
        .themedRows(grouped: true)
        .fileExporter(
            isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
            item: exporting, contentTypes: [.json], defaultFilename: exporting?.name
        ) { result in
            if case .failure(let error) = result { message = "Couldn't save the backup: \(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): read(url)
            case .failure(let error): message = "Couldn't open the file: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
            titleVisibility: .visible,
            presenting: restoring
        ) { backup in
            Button("Restore", role: .destructive) { restore(backup) }
        } message: { backup in
            Text(confirmation(backup))
        }
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func backUp() {
        do {
            let backup = try actions.make(includesHistory)
            exporting = BackupFile(data: try backup.encoded(), name: backup.suggestedFileName)
        } catch {
            message = error.message
        }
    }

    private func read(_ url: URL) {
        // A file from the Files picker is outside the app's own folder.
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        do {
            restoring = try AccountBackup.decode(try Data(contentsOf: url))
        } catch let error as BackupError {
            message = error.message
        } catch {
            message = "Couldn't read the file: \(error.localizedDescription)"
        }
    }

    private func restore(_ backup: AccountBackup) {
        do {
            try actions.restore(backup)
            message = "Restored the backup from \(backup.created.formatted(date: .abbreviated, time: .shortened))."
        } catch {
            message = error.message
        }
    }

    /// "From Oct 24, 2026 at 7:30 PM. …"
    private func confirmation(_ backup: AccountBackup) -> String {
        let what = backup.hasHistory
            ? "your settings, Wishlist, saved stations and play history"
            : "your settings, Wishlist and saved stations (play history stays as it is)"
        var text = "From \(backup.created.formatted(date: .abbreviated, time: .shortened)). On this iPhone, \(what) are replaced with the backup's."
        if actions.isFromAnotherAccount(backup) {
            text += " It's from a different server or user."
        }
        return text
    }
}

/// The backup as a file for the Files picker.
private struct BackupFile: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.name }
    }
}
