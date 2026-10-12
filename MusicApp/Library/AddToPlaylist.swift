import NavidromeCore
import Observation
import SwiftUI

/// What the Add to Playlist sheet is open for. Menus anywhere set it; the
/// screen on top presents the sheet (`addToPlaylistSheet`).
@MainActor
@Observable
final class AddToPlaylistRequest {
    struct Pending: Identifiable {
        let id = UUID()
        let source: PlaylistEditor.Source
        let title: String
    }

    var pending: Pending?

    /// The sheet shows its own errors while open.
    var isOpen: Bool { pending != nil }

    func open(_ source: PlaylistEditor.Source, title: String = "Add to Playlist") {
        pending = Pending(source: source, title: title)
    }
}

/// "Add to Playlist…" for a menu.
struct AddToPlaylistButton: View {
    let library: Library
    let source: PlaylistEditor.Source

    var body: some View {
        Button("Add to Playlist…", systemImage: "music.note.list") {
            library.addToPlaylist.open(source)
        }
    }
}

extension View {
    /// Presents the Add to Playlist sheet when a menu asks for it. Only the
    /// screen on top may present, so `isEnabled` is false while it is covered
    /// by another sheet (Now Playing presents its own).
    func addToPlaylistSheet(_ library: Library, isEnabled: Bool = true) -> some View {
        modifier(AddToPlaylistPresenter(library: library, isEnabled: isEnabled))
    }

    /// Briefly shows what the last playlist change did.
    func playlistConfirmation(_ editor: PlaylistEditor) -> some View {
        modifier(PlaylistConfirmation(editor: editor))
    }
}

private struct AddToPlaylistPresenter: ViewModifier {
    let library: Library
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.sheet(item: pending) { pending in
            AddToPlaylistSheet(library: library, pending: pending)
        }
    }

    private var pending: Binding<AddToPlaylistRequest.Pending?> {
        Binding(
            get: { isEnabled ? library.addToPlaylist.pending : nil },
            set: { if isEnabled { library.addToPlaylist.pending = $0 } }
        )
    }
}

/// "New Playlist…" first, then the user's playlists. Choosing one adds the
/// songs and closes the sheet; the confirmation shows on the screen beneath.
private struct AddToPlaylistSheet: View {
    let library: Library
    let pending: AddToPlaylistRequest.Pending

    @Environment(\.dismiss) private var dismiss
    @State private var isNaming = false
    @State private var newName = ""

    private var editor: PlaylistEditor { library.playlistEditor }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("New Playlist…", systemImage: "plus") {
                        newName = ""
                        isNaming = true
                    }
                    // An action, unlike the playlist rows below it.
                    .foregroundStyle(.tint)
                }
                .themedRows()
                Section {
                    playlistRows
                }
                .themedRows()
            }
            .listStyle(.plain)
            .themedList()
            .disabled(editor.isSaving)
            .overlay {
                if editor.isSaving { ProgressView() }
            }
            .navigationTitle(pending.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Playlist", isPresented: $isNaming) {
                TextField("Name", text: $newName)
                Button("Create") { run { await editor.create(named: newName, with: pending.source) } }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn't Save Playlist", isPresented: errorShown) {
                Button("OK") { editor.dismissError() }
            } message: {
                Text(editor.error ?? "")
            }
        }
        .task { await editor.loadPlaylists() }
    }

    @ViewBuilder
    private var playlistRows: some View {
        switch editor.playlists {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Try Again") { Task { await editor.loadPlaylists() } }
                    .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity)
        case .loaded(let playlists) where playlists.isEmpty:
            Text("You have no playlists yet.").foregroundStyle(.secondary)
        case .loaded(let playlists):
            ForEach(playlists) { playlist in
                Button {
                    run { await editor.add(pending.source, to: playlist) }
                } label: {
                    PlaylistRow(library: library, playlist: playlist)
                }
                .foregroundStyle(.primary)
            }
        }
    }

    /// Closes the sheet once the change has gone through; on failure it stays
    /// open with the error, so the user can try another playlist.
    private func run(_ change: @escaping () async -> Bool) {
        Task {
            if await change() { dismiss() }
        }
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { editor.error != nil }, set: { if !$0 { editor.dismissError() } })
    }
}

/// Cover, name and song count.
struct PlaylistRow: View {
    let library: Library
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(library: library, coverArtID: playlist.coverArtID, side: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name.isEmpty ? "Untitled" : playlist.name).lineLimit(1)
                if let count = playlist.songCount {
                    Text(count == 1 ? "1 song" : "\(count) songs").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(.rect)
    }
}

private struct PlaylistConfirmation: ViewModifier {
    let editor: PlaylistEditor

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message = editor.confirmation {
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect()
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { editor.dismissConfirmation() }
                    .task(id: message) {
                        AccessibilityNotification.Announcement(message).post()
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation { editor.dismissConfirmation() }
                    }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.default, value: editor.confirmation)
    }
}
