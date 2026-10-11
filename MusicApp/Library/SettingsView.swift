import NavidromeCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: StreamingSettingsModel
    let downloads: DownloadManager
    @Bindable var history: PlayHistory
    @State private var isConfirmingRemoveAll = false
    @State private var isConfirmingClearHistory = false

    var body: some View {
        Form {
            Section {
                qualityPicker("Wi-Fi", selection: $settings.settings.wifiQuality)
                qualityPicker("Cellular", selection: $settings.settings.cellularQuality)
            } header: {
                Text("Streaming Quality")
            } footer: {
                Text("Lower quality uses less data. Cellular also applies to hotspots and Low Data Mode. Changes apply from the next track.")
            }
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
        }
        .navigationTitle("Settings")
        .confirmationDialog("Clear all play history?", isPresented: $isConfirmingClearHistory, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { history.clear() }
        }
        .confirmationDialog("Remove all downloads?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
            Button("Remove All Downloads", role: .destructive) { downloads.removeAll() }
        }
    }

    private func qualityPicker(_ title: String, selection: Binding<StreamQuality>) -> some View {
        Picker(title, selection: selection) {
            ForEach(StreamQuality.allCases, id: \.self) { quality in
                Text(quality.title).tag(quality)
            }
        }
    }
}
