import NavidromeCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: StreamingSettingsModel
    let downloads: DownloadManager
    @State private var isConfirmingRemoveAll = false

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
        }
        .navigationTitle("Settings")
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
