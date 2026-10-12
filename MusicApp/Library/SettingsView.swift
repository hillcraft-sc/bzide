import NavidromeCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: StreamingSettingsModel
    let downloads: DownloadManager
    @Bindable var history: PlayHistory
    @Bindable var appearance: AppearanceModel
    let account: AccountSummary?
    let signOut: () -> Void
    @State private var isConfirmingRemoveAll = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingClearHistory = false

    var body: some View {
        Form {
            appearanceSection
            if let account {
                Section {
                    LabeledContent("Server", value: account.server)
                    LabeledContent("User", value: account.username)
                    Button("Sign Out", role: .destructive) { isConfirmingSignOut = true }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Downloads, history and the queue stay on this iPhone for when you sign back in. Signing in to a different server or user removes them.")
                }
                .themedRows(grouped: true)
            }
            Section {
                qualityPicker("Wi-Fi", selection: $settings.settings.wifiQuality)
                qualityPicker("Cellular", selection: $settings.settings.cellularQuality)
            } header: {
                Text("Streaming Quality")
            } footer: {
                Text("Lower quality uses less data. Cellular also applies to hotspots and Low Data Mode. Changes apply from the next track.")
            }
            .themedRows(grouped: true)
            Section {
                Toggle("Download over Cellular", isOn: $settings.settings.downloadOverCellular)
                LabeledContent("Storage Used", value: downloads.totalBytes.formatted(.byteCount(style: .file)))
                Button("Remove All Downloads", role: .destructive) { isConfirmingRemoveAll = true }
                    .disabled(downloads.collections.isEmpty)
            } header: {
                Text("Downloads")
            } footer: {
                Text("Downloads are stored in original quality. The cellular setting applies to downloads started after changing it.")
            }
            .themedRows(grouped: true)
            Section {
                Picker("Keep History For", selection: $history.retention) {
                    ForEach(HistoryRetention.allCases, id: \.self) { retention in
                        Text(retention.title).tag(retention)
                    }
                }
                Button("Clear History", role: .destructive) { isConfirmingClearHistory = true }
                    .disabled(history.entries.isEmpty)
            } header: {
                Text("Play History")
            } footer: {
                Text("History is kept on this iPhone only. A song is added once it has played for half its length or 4 minutes.")
            }
            .themedRows(grouped: true)
        }
        .themedList(grouped: true)
        .navigationTitle("Settings")
        .confirmationDialog("Sign out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { signOut() }
        } message: {
            Text("Playback stops. Your downloads and history stay unless you sign in to a different account.")
        }
        .confirmationDialog("Clear all play history?", isPresented: $isConfirmingClearHistory, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { history.clear() }
        }
        .confirmationDialog("Remove all downloads?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
            Button("Remove All Downloads", role: .destructive) { downloads.removeAll() }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $appearance.settings.theme) {
                Section {
                    ForEach([AppTheme.system, .light, .dark], id: \.self) { Text($0.title).tag($0) }
                }
                Section("Catppuccin") {
                    ForEach([AppTheme.latte, .frappe, .macchiato, .mocha], id: \.self) { Text($0.title).tag($0) }
                }
            }
            if let palette = appearance.palette {
                AccentPicker(palette: palette, selection: $appearance.settings.accent)
            }
        } header: {
            Text("Appearance")
        } footer: {
            if appearance.palette != nil {
                Text("Colours from Catppuccin (catppuccin.com).")
            }
        }
        .themedRows(grouped: true)
    }

    private func qualityPicker(_ title: String, selection: Binding<StreamQuality>) -> some View {
        Picker(title, selection: selection) {
            ForEach(StreamQuality.allCases, id: \.self) { quality in
                Text(quality.title).tag(quality)
            }
        }
    }
}

/// Catppuccin's 14 accents as swatches in the current flavour, the chosen one ticked.
private struct AccentPicker: View {
    let palette: CatppuccinPalette
    @Binding var selection: CatppuccinAccent

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accent")
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CatppuccinAccent.allCases, id: \.self) { accent in
                    swatch(accent)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ accent: CatppuccinAccent) -> some View {
        let isSelected = accent == selection
        return Button {
            selection = accent
        } label: {
            Circle()
                .fill(Color(palette.accent(accent)))
                .frame(width: 32, height: 32)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.footnote.bold())
                            .foregroundStyle(Color(palette.base))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
