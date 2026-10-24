import NavidromeCore
import SwiftUI

// The filter bar shared by Find Stations and the saved stations (Radio):
// buttons and menus that show their value when set, and a searchable picker.

/// A filter bar above a list, as plain content in a column. Not attached to
/// the list's edge (safeAreaInset or safeAreaBar): the navigation bar folds
/// whatever is attached there into its own area and hides or blurs it
/// depending on the large title and scroll position, differently on device.
struct FilterBarStack<Bar: View, Content: View>: View {
    var showsBar = true
    @ViewBuilder let bar: () -> Bar
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if showsBar {
                bar()
                Divider()
            }
            content()
        }
        // The bar on the theme's background, like the list below it.
        .themedList()
    }
}

enum FilterKind: String, Identifiable {
    case country, genre
    var id: String { rawValue }
}

/// A filter in the bar: its value when one is chosen, tinted.
struct FilterButton: View {
    let title: String
    let isSet: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FilterLabel(title: title, systemImage: "chevron.down", isSet: isSet)
        }
    }
}

struct FilterLabel: View {
    let title: String
    let systemImage: String
    let isSet: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1).truncationMode(.tail)
            Image(systemName: systemImage).imageScale(.small)
        }
        .font(.subheadline.weight(isSet ? .semibold : .regular))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(isSet ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .background(isSet ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
        .tapTarget()
    }
}

struct FilterOption: Identifiable {
    let id: String
    let title: String
    let count: Int
}

/// A searchable list to pick one filter value from, or Any.
struct FilterPicker<Item>: View {
    let title: String
    let anyTitle: String
    let state: LoadState<[Item]>
    let load: () async -> Void
    let selection: String?
    let option: (Item) -> FilterOption
    /// Shown above the rest under `pinnedTitle`, if it's in the list.
    let pinnedID: String?
    let pinnedTitle: String?
    let choose: (String?) -> Void

    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoadStateView(state: state, retry: load) { items in
                let options = items.map(option)
                let shown = search.isEmpty ? options : options.filter { $0.title.localizedStandardContains(search) }
                List {
                    if search.isEmpty {
                        Section {
                            row(id: nil, title: anyTitle, count: nil)
                        }
                        if let pinnedTitle, let pinned = options.first(where: { $0.id == pinnedID }) {
                            Section(pinnedTitle) {
                                row(id: pinned.id, title: pinned.title, count: pinned.count)
                            }
                        }
                    }
                    Section {
                        ForEach(shown) { row(id: $0.id, title: $0.title, count: $0.count) }
                    }
                }
                .overlay {
                    if shown.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func row(id: String?, title: String, count: Int?) -> some View {
        Button {
            choose(id)
            dismiss()
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if let count {
                    Text(count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                }
                if id == selection {
                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Selected")
                }
            }
            .contentShape(.rect)
        }
    }
}

/// Quality: any, or at least 128, 192, 256 or 320 kbps; reads e.g. "192+ kbps" when set.
struct QualityMenu: View {
    @Binding var minimumBitrate: Int?

    var body: some View {
        Menu {
            Picker("Quality", selection: $minimumBitrate) {
                Text("Any Quality").tag(Int?.none)
                ForEach(RadioBrowserClient.Query.bitrateChoices, id: \.self) { bitrate in
                    Text("\(bitrate) kbps or more").tag(Int?.some(bitrate))
                }
            }
        } label: {
            FilterLabel(title: minimumBitrate.map { "\($0)+ kbps" } ?? "Quality", systemImage: "chevron.down", isSet: minimumBitrate != nil)
        }
    }
}

/// The sort order: a compact button (⇅) whose menu shows the choices, the
/// current one checked.
struct SortMenu<Order: Hashable>: View {
    @Binding var selection: Order
    let options: [Order]
    let title: (Order) -> String

    var body: some View {
        Menu {
            Picker("Sort By", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(title(option)).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline)
                .frame(width: 34, height: 30)
                .background(.fill.tertiary, in: .capsule)
                .tapTarget()
        }
        .accessibilityLabel("Sort By")
        .accessibilityValue(title(selection))
    }
}

/// The filter bar shared by Find Stations and the saved stations: Country,
/// Genre and Quality, a clear button once any is set, and the sort order.
/// A plain row that fits the screen (long values are cut short), not a
/// scroll view: the navigation bar adopts the first scroll view under it for
/// its large title and edge effect, and drew over a scrolling bar.
struct StationFilterBar<Order: Hashable>: View {
    let country: String?
    let genre: String?
    @Binding var minimumBitrate: Int?
    @Binding var order: Order
    let orders: [Order]
    let orderTitle: (Order) -> String
    let pickCountry: () -> Void
    let pickGenre: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            FilterButton(title: country ?? "Country", isSet: country != nil, action: pickCountry)
            FilterButton(title: genre ?? "Genre", isSet: genre != nil, action: pickGenre)
            QualityMenu(minimumBitrate: $minimumBitrate)
            Spacer(minLength: 0)
            if country != nil || genre != nil || minimumBitrate != nil {
                Button("Clear Filters", systemImage: "xmark.circle.fill", action: clear)
                    .labelStyle(.tapTarget)
                    .foregroundStyle(.secondary)
            }
            SortMenu(selection: $order, options: orders, title: orderTitle)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
