import NavidromeCore
import SwiftUI

/// Now Playing's sleep timer: a moon that offers stop times, and once one is
/// running shows the time left (or that it stops at the end of the song).
struct SleepTimerMenu: View {
    let timer: SleepTimer

    var body: some View {
        Menu {
            if timer.mode != nil {
                Button("Turn Off Timer", systemImage: "moon.slash") { timer.cancel() }
                Divider()
            }
            ForEach(SleepTimer.minuteChoices, id: \.self) { minutes in
                Button(Self.title(minutes: minutes)) { timer.start(minutes: minutes) }
            }
            Button("End of Song") { timer.startEndOfSong() }
        } label: {
            label
        }
        .accessibilityLabel("Sleep Timer")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var label: some View {
        if timer.mode == nil {
            Label("Sleep Timer", systemImage: "moon.zzz")
        } else {
            // Counts down each second to when the music stops: the timer, or the
            // end of the song. Plain views, not a Label: a toolbar shows only a
            // label's icon.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 4) {
                    Image(systemName: "moon.zzz.fill")
                    Text(timer.stopsIn(at: context.date).map(Self.countdown) ?? "End")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(.tint)
            }
        }
    }

    private var accessibilityValue: String {
        switch timer.mode {
        case nil: "Off"
        case .endOfSong: "Stops at the end of the song" + (timer.stopsIn(at: .now).map { ", \(Self.countdown($0)) left" } ?? "")
        case .minutes: "\(Self.countdown(timer.remaining(at: .now) ?? 0)) left"
        }
    }

    static func title(minutes: Int) -> String {
        minutes == 60 ? "1 Hour" : "\(minutes) Minutes"
    }

    /// Minutes and seconds, e.g. "23:41".
    static func countdown(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
