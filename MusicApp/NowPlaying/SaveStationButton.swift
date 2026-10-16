import NavidromeCore
import SwiftUI

/// Now Playing's Save Station, for a station Spin the Dial is playing that
/// isn't saved yet (Now Playing decides, having loaded the saved stations):
/// saves it as + in Radio does (to the server for an admin, else to this
/// iPhone, offering this iPhone if the server refuses), with the details the
/// dial found. Then it reads "Saved"; a dialed station already saved reads
/// "In Your Stations".
struct SaveStationButton: View {
    enum Status {
        case unsaved, justSaved, alreadySaved
    }

    let library: Library
    let song: Song
    let stations: RadioStationsModel
    let status: Status
    let onSaved: () -> Void

    @State private var isSaving = false
    @State private var refusal: String?
    @State private var errorMessage: String?

    private var savable: SpinTheDialModel.Savable? { library.spinTheDial.savable(song) }

    var body: some View {
        Group {
            switch status {
            case .justSaved:
                Label("Saved", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            case .alreadySaved:
                Label("In Your Stations", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            case .unsaved:
                Button(action: { save(to: nil) }) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Label("Save Station", systemImage: "plus.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSaving)
            }
        }
        .frame(maxWidth: .infinity)
        .alert("Couldn't Save to Server", isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })) {
            Button("Save on This iPhone") { save(to: .phone) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(refusal ?? "")\n\nSave it on this iPhone instead?")
        }
        .alert("Couldn't Save Station", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save(to place: RadioStationsModel.Place?) {
        guard let savable else { return }
        let place = place ?? stations.newStationPlace
        isSaving = true
        Task {
            defer { isSaving = false }
            do throws(RadioStationsModel.ChangeError) {
                try await stations.add(savable.draft, details: savable.details, to: place)
                onSaved()
            } catch {
                if case .server(let reason) = error, place == .server {
                    refusal = reason
                } else {
                    errorMessage = error.message
                }
            }
        }
    }
}
