import NavidromeCore
import PhotosUI
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: StreamingSettingsModel
    let downloads: DownloadManager
    @Bindable var history: PlayHistory
    @Bindable var appearance: AppearanceModel
    @Bindable var profile: ProfileModel
    let account: AccountSummary?
    let signOut: () -> Void
    /// The bare player screen kept for exercising playback.
    let debugPlayer: () -> DebugPlayerView
    @State private var isConfirmingRemoveAll = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingClearHistory = false
    @State private var photoItem: PhotosPickerItem?
    /// Why the last picked picture couldn't be used.
    @State private var pickError: String?

    var body: some View {
        Form {
            appearanceSection
            if let account {
                Section {
                    HStack(spacing: 14) {
                        AvatarImage(data: profile.avatar, side: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.username).font(.headline)
                            Text(account.server).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Signed in as \(account.username) on \(account.server)")
                    Button("Sign Out", role: .destructive) { isConfirmingSignOut = true }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Downloads, history and the queue stay on this iPhone for when you sign back in. Signing in to a different server or user removes them.")
                }
                .themedRows(grouped: true)
            }
            profileSection
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
                Picker("Volume Normalization", selection: $settings.settings.volumeNormalization) {
                    ForEach(VolumeNormalization.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Keep Spinning", isOn: $settings.settings.keepSpinning)
            } header: {
                Text("Playback")
            } footer: {
                Text("Volume Normalization evens out loudness between songs using ReplayGain, so quiet older recordings and loud modern ones play at a similar volume; By Album keeps the differences within an album. It needs ReplayGain tags in your music files; songs without them play unchanged, and Now Playing shows the adjustment beside the quality.\n\nKeep Spinning: when the queue reaches its last song, Bzide spins off from it so the music keeps going, with similar songs if your server has them (Navidrome with Last.fm), otherwise a mix from your library. Repeat turns it off.")
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

    /// Where the profile picture comes from, then what's needed for that choice.
    private var profileSection: some View {
        Section {
            Picker("Picture", selection: $profile.settings.picture) {
                ForEach(ProfileModel.Picture.allCases, id: \.self) { picture in
                    Text(picture.title).tag(picture)
                }
            }
            switch profile.settings.picture {
            case .none:
                EmptyView()
            case .contactCard:
                Button(profile.hasPicked(.contactCard) ? "Choose Another Contact Card…" : "Choose Contact Card…") {
                    ContactPhotoPicker.present { photo in usePicked(photo, for: .contactCard) }
                }
                pickedStatus(.contactCard)
            case .photo:
                photoPicker(title: profile.hasPicked(.photo) ? "Choose Another Photo…" : "Choose Photo…")
                pickedStatus(.photo)
            case .gravatar:
                TextField("Email", text: $profile.settings.customEmail, prompt: Text(profile.serverEmail ?? "you@example.com"))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                gravatarStatus
            }
        } header: {
            Text("Profile")
        } footer: {
            Text(profileFooter)
        }
        .themedRows(grouped: true)
        // Shown on choosing; Gravatar is looked up once typing pauses.
        .task(id: "\(profile.settings.picture)|\(profile.settings.customEmail)") {
            if profile.settings.picture == .gravatar {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
            }
            await profile.refresh()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                usePicked(data, for: .photo)
                photoItem = nil
            }
        }
    }

    /// The photo picker's label closure may run off the main actor, so it gets
    /// its title ready-made rather than reading the profile itself.
    private func photoPicker(title: String) -> some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Text(title)
        }
    }

    /// Saves a picked picture, or says why it couldn't be used.
    private func usePicked(_ data: Data?, for picture: ProfileModel.Picture) {
        pickError = nil
        guard let data else { return }
        guard let sized = ProfilePictureSizer.profileJPEG(from: data) else {
            pickError = "That picture couldn't be read. Try another."
            return
        }
        profile.setPicked(sized, for: picture)
    }

    @ViewBuilder
    private func pickedStatus(_ picture: ProfileModel.Picture) -> some View {
        if let pickError {
            Text(pickError).foregroundStyle(.secondary)
        } else if profile.hasPicked(picture), let avatar = profile.avatar {
            HStack {
                Text("Current picture")
                Spacer()
                AvatarImage(data: avatar, side: 32)
            }
        }
    }

    @ViewBuilder
    private var gravatarStatus: some View {
        switch profile.lookup {
        case .off:
            EmptyView()
        case .loading:
            HStack {
                Text("Looking for your Gravatar…").foregroundStyle(.secondary)
                Spacer()
                ProgressView()
            }
        case .found:
            HStack {
                Text("Gravatar found")
                Spacer()
                AvatarImage(data: profile.avatar, side: 32)
            }
        case .notFound:
            Text("No Gravatar for this email.").foregroundStyle(.secondary)
        case .noEmail:
            Text("Your account has no email. Enter one above.").foregroundStyle(.secondary)
        case .invalidEmail:
            Text("That doesn't look like an email address.").foregroundStyle(.secondary)
        case .failed:
            Text("Couldn't reach Gravatar. It will try again later.").foregroundStyle(.secondary)
        }
    }

    private var profileFooter: String {
        switch profile.settings.picture {
        case .none:
            return "Choose a picture to show on the Settings button and here. iOS doesn't let apps use your Apple Account photo; your contact card is usually the same picture."
        case .contactCard:
            return "Pick yourself in Contacts. Bzide copies that one photo and can't see your other contacts. Pick again after changing it."
        case .photo:
            return "Bzide copies the photo you pick and can't see the rest of your library."
        case .gravatar:
            let base = "Looks up your Gravatar (gravatar.com). This sends a scrambled form (a hash) of the email to Gravatar, never the address itself."
            if let serverEmail = profile.serverEmail {
                return base + " Leave Email empty to use your account's email (\(serverEmail))."
            }
            return base
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

/// A round profile picture, or a person symbol when there's none.
struct AvatarImage: View {
    let data: Data?
    let side: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                // Original colors: toolbars otherwise draw images as one-color shapes.
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}
