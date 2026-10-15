import NavidromeCore
import SwiftUI

/// The Add Station and Edit Station form: a name, the stream address and an
/// optional homepage. A new station is saved on the server for an admin, else
/// on this iPhone; an edited one stays where it is. If saving fails, the form
/// stays open with the reason, and if the server refused a new station, it
/// offers to save it on this iPhone instead.
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
    /// The server's reason for refusing a new station.
    @State private var refusal: String?
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
                Section {
                    addressField("https://example.com", text: $draft.homePageURL)
                } header: {
                    Text("Homepage (Optional)")
                } footer: {
                    Text(placeNote)
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
            .alert("Couldn't Save to Server", isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })) {
                Button("Save on This iPhone", action: saveOnPhone)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(refusal ?? "")\n\nSave it on this iPhone instead?")
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var placeNote: String {
        let onPhone = switch target {
        case .new: model.newStationPlace == .phone
        case .edit(let station): station.isOnPhone
        }
        return onPhone ? "Saved on this iPhone." : "Saved on your server, for every app that uses it."
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
                if case .server(let reason) = error, case .new = target, model.newStationPlace == .server {
                    refusal = reason
                } else {
                    errorMessage = error.message
                }
            }
        }
    }

    private func saveOnPhone() {
        Task {
            do throws(RadioStationsModel.ChangeError) {
                try await model.add(draft, to: .phone)
                dismiss()
            } catch {
                errorMessage = error.message
            }
        }
    }
}
