import NavidromeCore
import SwiftUI

/// What's been played, newest first and grouped by day, filtered by text and period.
struct HistoryView: View {
    let library: Library
    @State private var query = ""
    @State private var period: HistoryPeriod = .all
    @State private var isPickingRange = false

    var body: some View {
        let days = library.history.days(matching: query, in: period)
        List {
            ForEach(days) { day in
                Section(Self.dayTitle(day.day)) {
                    ForEach(day.items) { item in
                        Button {
                            library.engine.play(songs: [item.entry.song])
                        } label: {
                            HistoryRow(
                                item: item, isCurrent: item.entry.song.id == library.engine.queue.current?.song.id,
                                isFavorite: library.isFavorite(item.entry.song), stars: library.stars(of: item.entry.song)
                            )
                        }
                        .foregroundStyle(.primary)
                        .contextMenu { SongActions(library: library, song: item.entry.song) }
                        .siriEntity(songID: item.entry.song.id)
                    }
                }
            }
            .themedRows()
        }
        .listStyle(.plain)
        .themedList()
        .overlay {
            if library.history.entries.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Songs appear here once they've played for half their length or 4 minutes.")
                )
            } else if days.isEmpty {
                ContentUnavailableView("No Plays", systemImage: "magnifyingglass", description: Text("Nothing matches this search and period."))
            }
        }
        .navigationTitle("History")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Track, artist, album")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Period", selection: $period) {
                        ForEach(HistoryPeriod.presets, id: \.self) { preset in
                            Text(preset.title).tag(preset)
                        }
                        if case .custom = period {
                            Text(Self.rangeTitle(period)).tag(period)
                        }
                    }
                    Button("Choose Dates…", systemImage: "calendar") { isPickingRange = true }
                    Divider()
                    Toggle("Show Every Play", isOn: showsEveryPlay)
                } label: {
                    Label(period.title, systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $isPickingRange) {
            DateRangePicker(period: $period)
        }
    }

    /// Off by default: a song played several times in a day shows once, with a count.
    private var showsEveryPlay: Binding<Bool> {
        Binding(get: { !library.history.combinesRepeats }, set: { library.history.combinesRepeats = !$0 })
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day().year())
    }

    private static func rangeTitle(_ period: HistoryPeriod) -> String {
        guard case .custom(let from, let to) = period else { return period.title }
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(min(from, to).formatted(format)) – \(max(from, to).formatted(format))"
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    let isCurrent: Bool
    let isFavorite: Bool
    let stars: Int?

    private var entry: PlayHistoryEntry { item.entry }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.song.title.isEmpty ? "Untitled" : entry.song.title)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text([entry.song.artist, entry.song.album].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            SongMarks(isFavorite: isFavorite, stars: stars)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.playedAt.formatted(date: .omitted, time: .shortened))
                if item.playCount > 1 {
                    Text("\(item.playCount) plays")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }
}

/// Picks a custom date range for the history.
private struct DateRangePicker: View {
    @Binding var period: HistoryPeriod
    @Environment(\.dismiss) private var dismiss
    @State private var from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var to = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: $from, in: ...Date(), displayedComponents: .date)
                    DatePicker("To", selection: $to, in: ...Date(), displayedComponents: .date)
                }
                .themedRows(grouped: true)
            }
            .themedList(grouped: true)
            .navigationTitle("Choose Dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") {
                        period = .custom(from: from, to: to)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
