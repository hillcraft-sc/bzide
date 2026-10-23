import NavidromeCore
import Observation
import SwiftUI

/// The playlist a menu asked to rename or delete. Menus can't hold an alert,
/// so they set this and the screen on top asks (`playlistPrompts`).
@MainActor
@Observable
final class PlaylistPrompts {
    var renaming: Playlist?
    var deleting: Playlist?
}

/// Rename…, Share Playlist and Delete Playlist… for a playlist the user owns;
/// nothing for anyone else's. In the Playlists list's long-press menu and the
/// playlist page's ⋯ menu.
struct PlaylistManageButtons: View {
    let library: Library
    let playlist: Playlist

    var body: some View {
        if library.playlistEditor.isOwned(playlist) {
            Section {
                Button("Rename…", systemImage: "pencil") {
                    library.playlistPrompts.renaming = playlist
                }
                // A toggle so the menu draws the checkmark while it's shared.
                Toggle("Share Playlist", systemImage: "person.2", isOn: Binding(
                    get: { playlist.isPublic == true },
                    set: { shared in Task { await library.playlistEditor.setShared(playlist, shared) } }
                ))
                Button("Delete Playlist…", systemImage: "trash", role: .destructive) {
                    library.playlistPrompts.deleting = playlist
                }
            }
        }
    }
}

extension View {
    /// Asks for a playlist's new name or to confirm deleting it, when a menu
    /// asks, and shows playlist changes that failed. Only the screen on top may
    /// present, so `isEnabled` is false while it is covered (Now Playing).
    func playlistPrompts(_ library: Library, isEnabled: Bool = true) -> some View {
        modifier(PlaylistPromptsPresenter(library: library, isEnabled: isEnabled))
    }
}

private struct PlaylistPromptsPresenter: ViewModifier {
    let library: Library
    let isEnabled: Bool
    @State private var newName = ""
    /// Kept here: the prompt's binding clears the request as it closes.
    @State private var renameTarget: Playlist?
    @State private var deleteTarget: Playlist?

    private var prompts: PlaylistPrompts { library.playlistPrompts }
    private var editor: PlaylistEditor { library.playlistEditor }

    func body(content: Content) -> some View {
        content
            .alert("Rename Playlist", isPresented: shown(prompts.renaming) { prompts.renaming = nil }) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    guard let playlist = renameTarget else { return }
                    let name = newName
                    Task { await editor.rename(playlist, to: name) }
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: prompts.renaming?.id) {
                guard let playlist = prompts.renaming else { return }
                renameTarget = playlist
                newName = playlist.name
            }
            .onChange(of: prompts.deleting?.id) {
                if let playlist = prompts.deleting { deleteTarget = playlist }
            }
            .confirmationDialog(
                deleteTitle, isPresented: shown(prompts.deleting) { prompts.deleting = nil }, titleVisibility: .visible
            ) {
                Button("Delete Playlist", role: .destructive) {
                    guard let playlist = deleteTarget else { return }
                    Task { await editor.delete(playlist) }
                }
            } message: {
                Text(deleteMessage)
            }
            // The Add to Playlist sheet shows its own errors while open.
            .alert("Couldn't Save Playlist", isPresented: shown(isEnabled && !library.addToPlaylist.isOpen ? editor.error : nil) {
                editor.dismissError()
            }) {
                Button("OK") { editor.dismissError() }
            } message: {
                Text(editor.error ?? "")
            }
    }

    private var deleteTitle: String {
        "Delete “\(deleteTarget?.name ?? "")”?"
    }

    private var deleteMessage: String {
        let downloaded = deleteTarget.map {
            library.downloads.collection(id: DownloadCollection.id(.playlist, serverID: $0.id)) != nil
        } ?? false
        return downloaded
            ? "It's deleted from your server and its download is removed. The songs stay in your library."
            : "It's deleted from your server. The songs stay in your library."
    }

    /// Shown while `value` is set and this screen is on top; dismissing clears it.
    private func shown<Value>(_ value: Value?, clear: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: { isEnabled && value != nil }, set: { if !$0 { clear() } })
    }
}
