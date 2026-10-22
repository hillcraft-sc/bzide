import NavidromeCore

/// The app's side of the widgets' buttons (PlaybackIntentDefinitions.swift):
/// the same as the lock screen's and the Home Screen quick actions'.
@MainActor
enum WidgetPlayback {
    static func perform(_ command: WidgetCommand) async {
        guard let library = AppModel.shared.library else { return }
        let engine = library.engine
        switch command {
        case .togglePlayPause: engine.togglePlayPause()
        case .next: engine.next()
        case .previous: engine.previous()
        case .resume: engine.play()
        // Awaited, so the system keeps the app running until the music starts.
        case .randomMix: await library.randomMix.start()
        case .myCuts: await library.spinOff.startRated()
        }
    }
}
