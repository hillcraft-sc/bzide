import NavidromeCore

/// The app's side of the widget's buttons (PlaybackIntentDefinitions.swift):
/// the same as the lock screen's.
@MainActor
enum WidgetPlayback {
    static func perform(_ command: WidgetCommand) {
        guard let engine = AppModel.shared.library?.engine else { return }
        switch command {
        case .togglePlayPause: engine.togglePlayPause()
        case .next: engine.next()
        case .previous: engine.previous()
        }
    }
}
