import NavidromeCore
import SwiftUI

struct QueueList: View {
    let engine: PlaybackEngine

    var body: some View {
        if engine.queue.isEmpty {
            Text("Empty").foregroundStyle(.secondary)
        }
        ForEach(engine.queue.fromCurrent) { entry in
            Button {
                engine.jump(to: entry.id)
            } label: {
                HStack {
                    TitleRow(title: entry.song.title, subtitle: entry.song.artist)
                    Spacer()
                    if entry.id == engine.queue.current?.id {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Current")
                    }
                }
            }
            .foregroundStyle(.primary)
            .siriEntity(songID: entry.song.id)
        }
    }
}
