import NavidromeCore
import SwiftUI

extension View {
    /// The app's messages from anywhere (a favorite or rating that didn't
    /// save, a station that wouldn't play, a confirmation for a big artist,
    /// Spin Off's and Spin the Dial's banners and errors…), shown on whichever
    /// screen is on top: the library, Now Playing, or the visualizer or Lyrics
    /// over it. Each screen passes `isEnabled` false while another covers it,
    /// so a message isn't left behind it.
    func appMessages(_ library: Library?, isEnabled: Bool = true) -> some View {
        modifier(AppMessages(library: library, isEnabled: isEnabled))
    }
}

private struct AppMessages: ViewModifier {
    let library: Library?
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if let library {
            content.modifier(Messages(library: library, isEnabled: isEnabled))
        } else {
            content
        }
    }
}

private struct Messages: ViewModifier {
    let library: Library
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .noticeBanner(isEnabled ? library.playlistEditor.confirmation : nil) { library.playlistEditor.dismissConfirmation() }
            .noticeBanner(isEnabled ? library.spinOff.notice : nil, seconds: 5) { library.spinOff.dismissNotice() }
            .noticeBanner(isEnabled ? library.spinTheDial.notice : nil, seconds: 4) { library.spinTheDial.dismissNotice() }
            .alert("Couldn't Change Favorite", isPresented: shown(library.stars.error) { library.stars.dismissError() }) {
                Button("OK") { library.stars.dismissError() }
            } message: {
                Text(library.stars.error ?? "")
            }
            .alert("Couldn't Change Rating", isPresented: shown(library.ratings.error) { library.ratings.dismissError() }) {
                Button("OK") { library.ratings.dismissError() }
            } message: {
                Text(library.ratings.error ?? "")
            }
            .alert("Couldn't Play Station", isPresented: shown(library.radio.error) { library.radio.dismissError() }) {
                Button("OK") { library.radio.dismissError() }
            } message: {
                Text(library.radio.error ?? "")
            }
            .alert("Couldn't Load Songs", isPresented: shown(library.quickActions.error) { library.quickActions.dismissError() }) {
                Button("OK") { library.quickActions.dismissError() }
            } message: {
                Text(library.quickActions.error ?? "")
            }
            .alert("Spin the Dial", isPresented: shown(library.spinTheDial.error) { library.spinTheDial.dismissError() }) {
                Button("OK") { library.spinTheDial.dismissError() }
            } message: {
                Text(library.spinTheDial.error ?? "")
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(
                    get: { isEnabled && library.quickActions.confirmation != nil },
                    set: { if !$0 { library.quickActions.cancelConfirmation() } }
                ),
                titleVisibility: .visible,
                presenting: library.quickActions.confirmation
            ) { confirmation in
                Button(Self.confirmButton(confirmation.action)) {
                    Task { await library.quickActions.confirm() }
                }
                Button("Cancel", role: .cancel) { library.quickActions.cancelConfirmation() }
            }
    }

    /// Showing while there's a message and this screen is on top.
    private func shown(_ message: String?, dismiss: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: { isEnabled && message != nil }, set: { if !$0 { dismiss() } })
    }

    /// "Add 340 songs by Artist to the queue?"
    private var confirmationTitle: String {
        guard let confirmation = library.quickActions.confirmation else { return "" }
        let songs = "\(confirmation.songCount) songs by \(confirmation.artist.name)"
        return switch confirmation.action {
        case .play: "Play \(songs)?"
        case .shuffle: "Shuffle \(songs)?"
        case .playNext: "Play \(songs) next?"
        case .addToQueue: "Add \(songs) to the queue?"
        case .addToPlaylist: "Add \(songs) to a playlist?"
        case .download: "Download \(songs)?"
        }
    }

    private static func confirmButton(_ action: QuickActions.Action) -> String {
        switch action {
        case .play: "Play"
        case .shuffle: "Shuffle"
        case .playNext: "Play Next"
        case .addToQueue: "Add to Queue"
        case .addToPlaylist: "Choose Playlist"
        case .download: "Download"
        }
    }
}
