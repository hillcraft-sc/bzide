import NavidromeCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: StreamingSettingsModel
    let downloads: DownloadManager
    @Bindable var history: PlayHistory
    @Bindable var appearance: AppearanceModel
    let account: AccountSummary?
    let signOut: () -> Void
    /// The bare player screen kept for exercising playback.
    let debugPlayer: () -> DebugPlayerView
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
                qualityPicker("Download Quality", selection: $settings.settings.downloadQuality)
                Toggle("Download over Cellular", isOn: $settings.settings.downloadOverCellular)
                LabeledContent("Storage Used", value: downloads.totalBytes.formatted(.byteCount(style: .file)))
                Button("Remove All Downloads", role: .destructive) { isConfirmingRemoveAll = true }
                    .disabled(downloads.collections.isEmpty)
            } header: {
                Text("Downloads")
            } footer: {
                Text("Below Original, the server converts songs to MP3 as they download, which saves space. Quality and cellular changes apply to songs downloaded afterwards; songs already downloaded stay as they are.")
            }
            .themedRows(grouped: true)
            Section {
                Toggle("Find Lyrics Online", isOn: $settings.settings.findLyricsOnline)
            } header: {
                Text("Lyrics")
            } footer: {
                Text("When your server has no lyrics for a song, or only unsynced ones, look them up on LRCLIB (lrclib.net), a free lyrics database. This sends the song's title, artist, album and length there.")
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
            Section {
                NavigationLink {
                    debugPlayer()
                } label: {
                    Label("Debug Player", systemImage: "ladybug")
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("A bare player for testing playback.")
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
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Accent")
                        Spacer()
                        Text(appearance.settings.accent.title).foregroundStyle(.secondary)
                    }
                    SwatchGrid(
                        options: CatppuccinAccent.allCases,
                        color: { Color(palette.accent($0)) },
                        title: \.title,
                        isSelected: { $0 == appearance.settings.accent },
                        checkmark: Color(palette.base),
                        choose: { appearance.settings.accent = $0 }
                    )
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Accent")
                        Spacer()
                        Text(appearance.settings.systemAccent.title).foregroundStyle(.secondary)
                    }
                    SwatchGrid(
                        options: SystemAccent.allCases,
                        color: \.color,
                        title: \.title,
                        isSelected: { $0 == appearance.settings.systemAccent },
                        checkmark: .white,
                        choose: { appearance.settings.systemAccent = $0 }
                    )
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Appearance")
        } footer: {
            if appearance.palette != nil {
                Text("Colors from Catppuccin (catppuccin.com).")
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
