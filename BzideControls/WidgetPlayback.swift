/// The extension's side of the widget's buttons. They're audio playback
/// intents, which the system runs in the app; this only runs if one is run
/// here instead, where there's no player, so it does nothing.
enum WidgetPlayback {
    static func perform(_ command: WidgetCommand) {}
}
