import NavidromeCore
import SwiftUI

/// The Add Station and Edit Station form: a name, the stream address and an
/// optional homepage. Saving goes to the server; the form stays open with the
/// reason if it fails.
struct StationEditor: View {
    enum Target: Identifiable {
        case new
        case edit(RadioStation)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let station): station.id
            }
        }
    }

    let model: RadioStationsModel
    let target: Target

    @State private var draft: RadioStationDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(model: RadioStationsModel, target: Target) {
        self.model = model
        self.target = target
        switch target {
        case .new: _draft = State(initialValue: RadioStationDraft())
        case .edit(let station): _draft = State(initialValue: RadioStationDraft(station))
        }
    }

    private var title: String {
        if case .new = target { "Add Station" } else { "Edit Station" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Left blank, the stream's address is used.")
                }
                Section {
                    addressField("https://example.com/stream", text: $draft.streamURL)
                } header: {
                    Text("Stream")
                } footer: {
                    Text("A direct stream, or a .pls or .m3u playlist.")
                }
                Section("Homepage (Optional)") {
                    addressField("https://example.com", text: $draft.homePageURL)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", role: .confirm, action: save)
                            .disabled(draft.streamURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .alert("Couldn't Save Station", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func addressField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do throws(RadioStationsModel.ChangeError) {
                switch target {
                case .new: try await model.add(draft)
                case .edit(let station): try await model.update(station, to: draft)
                }
                dismiss()
            } catch {
                errorMessage = error.message
            }
        }
    }
}
