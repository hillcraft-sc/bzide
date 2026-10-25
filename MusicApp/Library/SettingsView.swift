import NavidromeCore
import PhotosUI
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: StreamingSettingsModel
    let equalizer: EqualizerModel
    let engine: PlaybackEngine
    let downloads: DownloadManager
    @Bindable var history: PlayHistory
    let wishlist: Wishlist
    @Bindable var appearance: AppearanceModel
    @Bindable var profile: ProfileModel
    let account: AccountSummary?
    let signOut: () -> Void
    let restoreDefaults: () -> Void
    let backup: BackupActions
    /// The bare player screen kept for exercising playback; `nil` outside
    /// Debug builds, so TestFlight and the App Store don't have it (#24).
    let debugPlayer: (() -> AnyView)?
    /// Radio Browser's genres, for Spin the Dial's Genres.
    let stationSearch: () -> StationSearchModel
    /// Fetches the library's lists again now.
    let refreshLibrary: () async throws -> Void
    @State private var refreshState = RefreshState.idle

    private enum RefreshState: Equatable {
        case idle, refreshing, done
        case failed(String)
    }
    @State private var isConfirmingRemoveAll = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingClearHistory = false
    @State private var isConfirmingRestoreDefaults = false
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
                    Button {
                        refresh()
                    } label: {
                        HStack {
                            Text("Refresh Library")
                            Spacer()
                            switch refreshState {
                            case .idle: EmptyView()
                            case .refreshing: ProgressView()
                            case .done: Image(systemName: "checkmark").foregroundStyle(.secondary)
                            case .failed: Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(refreshState == .refreshing)
                    Button("Sign Out", role: .destructive) { isConfirmingSignOut = true }
                } header: {
                    Text("Account")
                } footer: {
                    if case .failed(let message) = refreshState {
                        Text("Couldn't refresh: \(message)")
                    } else {
                        Text("Refresh Library fetches your library again now, so new music, ratings and favorites show at once in Search's filters, Spin It Back and Mix My Cuts, which otherwise keep their copy for 30 minutes. Downloads, history and the queue stay on this iPhone for when you sign back in. Signing in to a different server or user removes them.")
                    }
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
                Toggle("Play When CarPlay Connects", isOn: $settings.settings.playWhenCarPlayConnects)
            } header: {
                Text("CarPlay")
            } footer: {
                Text("Off: getting into the car doesn't start the music. Some cars tell the music app to play as soon as they connect, over CarPlay or Bluetooth; Bzide ignores that for a few seconds after connecting, then plays when you press play. On: the car can start Bzide where you left off.")
            }
            .themedRows(grouped: true)
            Section {
                Toggle("Use Simplified Rating", isOn: $settings.settings.useSimplifiedRating)
            } header: {
                Text("Ratings")
            } footer: {
                Text(settings.settings.useSimplifiedRating
                    ? "Rate songs, albums and artists Meh, Like or Love. Your server stores them as 1, 3 and 5 stars, so other apps show them as stars."
                    : "Rate songs, albums and artists with 1 to 5 stars, as in Navidrome. Turn this on to rate Meh, Like or Love instead.")
            }
            .themedRows(grouped: true)
            Section {
                Picker("Volume Normalization", selection: $settings.settings.volumeNormalization) {
                    ForEach(VolumeNormalization.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Keep Spinning", isOn: $settings.settings.keepSpinning)
                Toggle(settings.settings.useSimplifiedRating ? "Include Meh Songs" : "Include 1–2 Star Songs", isOn: $settings.settings.includeMehInMixes)
                Toggle("Include Favorites in My Cuts", isOn: $settings.settings.myCutsIncludeFavorites)
                Toggle("Sync Queue with Server", isOn: $settings.settings.syncQueueWithServer)
            } header: {
                Text("Playback")
            } footer: {
                Text("Volume Normalization evens out loudness between songs using ReplayGain, so quiet older recordings and loud modern ones play at a similar volume; By Album keeps the differences within an album. It needs ReplayGain tags in your music files; songs without them play unchanged, and Now Playing shows the adjustment beside the quality.\n\nKeep Spinning: when the queue reaches its last song, Bzide spins off from it so the music keeps going, with similar songs if your server has them (Navidrome with Last.fm), otherwise a mix from your library. Repeat turns it off.\n\n\(mixesFooter)\n\nSync Queue with Server saves the queue on your server, so you can continue on another device or in another app that uses the server's queue. When a newer queue is there, Bzide asks before playing it. Radio stations aren't saved.")
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
                Toggle("Mark Incomplete Albums", isOn: $settings.settings.markIncompleteAlbums)
                Toggle("Look Up Artists Online", isOn: $settings.settings.lookUpArtistsOnline)
            } header: {
                Text("Artists")
            } footer: {
                Text("Mark Incomplete Albums: an artist's page marks the albums you don't have all of, and an album's page says which tracks are missing. To do this, Bzide reads each of the artist's albums from your server the first time you open them.\n\nLook Up Artists Online: an artist's page adds their biography from Wikipedia and lists the releases you don't have, from MusicBrainz (musicbrainz.org), with covers from the Cover Art Archive; with Mark Incomplete Albums, MusicBrainz also gives each album's full track count. They get only the artist's name or MusicBrainz ID. Answers are kept on this iPhone for two weeks.")
            }
            .themedRows(grouped: true)
            Section {
                Toggle("Find Lyrics Online", isOn: $settings.settings.findLyricsOnline)
                if settings.settings.findLyricsOnline {
                    Toggle("Wrong Lyrics Button", isOn: $settings.settings.wrongLyricsButton)
                }
            } header: {
                Text("Lyrics")
            } footer: {
                Text("When your server has no lyrics for a song, or only unsynced ones, look them up on LRCLIB (lrclib.net), a free lyrics database. This sends the song's title, artist, album and length there." + (settings.settings.findLyricsOnline ? "\n\nWrong Lyrics Button: when LRCLIB's lyrics are for another version of the song, a button on the lyrics screen tries its next match, or stops using LRCLIB for that song. Your choice is remembered for the song." : "") + "\n\nTip: if your server runs Navidrome 0.63 or later, its admin can install the Navidrome Lyrics Plugin (nd-lyrics, github.com/J0R6IT0/navidrome-lyrics-plugin). The server then finds lyrics online itself, for every app, and Bzide shows them as your server's, with Find Lyrics Online left off.")
            }
            .themedRows(grouped: true)
            Section {
                NavigationLink {
                    EqualizerView(equalizer: equalizer, engine: engine)
                } label: {
                    LabeledContent("Equalizer", value: equalizer.summary)
                }
            } footer: {
                Text("Shapes the sound of songs on this iPhone, its headphones and Bluetooth (not radio stations or AirPlay). Kept on this iPhone, whichever account is signed in.")
            }
            .themedRows(grouped: true)
            Section {
                Toggle("Visualizer", isOn: $settings.settings.showsVisualizer)
            } header: {
                Text("Visualizer")
            } footer: {
                Text("Off, Now Playing has no visualizer button, so none of the visualizations can be opened. With Reduce Motion on (Settings > Accessibility > Motion), the visualizer asks before it starts moving.")
            }
            .themedRows(grouped: true)
            Section {
                Toggle("Live Weather", isOn: $settings.settings.liveWeather)
                if settings.settings.liveWeather {
                    Picker("Source", selection: $settings.settings.liveWeatherSource) {
                        ForEach(LiveWeatherProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("Use My Location", isOn: $settings.settings.liveWeatherUsesLocation)
                    LiveWeatherPlaceField(settings: settings)
                }
            } header: {
                Text("Weather (Live)")
            } footer: {
                Text("The Weather (Live) visualizer can show the real weather where you are, from Apple Weather or MET Norway (api.met.no; data CC BY 4.0). Apple Weather uses observations and radar where it has them, so it more often matches the sky outside; when it can't be reached, MET Norway is used. Either gets your approximate location, rounded to about a kilometer, while the visualizer is open. Use My Location asks for your location once. Place is used when location is off or unavailable: a city and state (“Springfield, IL”) or a ZIP code; elsewhere, a postal code with the country (“10115 Germany”). It's looked up by Apple, and the match shows under it. Off, it shows the time of day only.")
            }
            .themedRows(grouped: true)
            Section {
                Toggle("Find Stations Online", isOn: $settings.settings.findStationsOnline)
                Toggle("Look Up Songs Online", isOn: $settings.settings.lookUpSongsOnline)
            } header: {
                Text("Radio")
            } footer: {
                Text(StationSearchView.optInExplanation + "\n\nLook Up Songs Online: for the song a station is playing, Song Info and its album cover come from MusicBrainz (musicbrainz.org) and the Cover Art Archive, which get only its artist and title.")
            }
            .themedRows(grouped: true)
            WishlistSection(wishlist: wishlist)
            Section {
                Picker("Mode", selection: $settings.settings.spinTheDial.mode) {
                    ForEach(DialSettings.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("My Country Only", isOn: $settings.settings.spinTheDial.myCountryOnly)
                NavigationLink {
                    DialGenresView(makeModel: stationSearch, genres: $settings.settings.spinTheDial.genres)
                } label: {
                    LabeledContent("Genres", value: dialGenresSummary)
                }
                Picker("Minimum Quality", selection: $settings.settings.spinTheDial.minimumBitrate) {
                    Text("Any").tag(Int?.none)
                    ForEach(RadioBrowserClient.Query.bitrateChoices, id: \.self) { Text("\($0) kbps").tag(Int?.some($0)) }
                }
            } header: {
                Text("Spin the Dial")
            } footer: {
                Text(settings.settings.findStationsOnline
                    ? Self.dialExplanation(settings.settings.spinTheDial.mode)
                    : "Spin the Dial finds stations on Radio Browser, so it needs Find Stations Online. Turn that on above to use it.")
            }
            // It uses Radio Browser: off with Find Stations Online.
            .disabled(!settings.settings.findStationsOnline)
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
            // Scrobbling is set up on the server (Gitea #18).
            Section {
                Toggle("Send Plays to Server", isOn: $settings.settings.sendPlaysToServer)
            } header: {
                Text("Scrobbling")
            } footer: {
                Text("Bzide tells your server what's playing and records each play once it has played for half its length or 4 minutes (plays made offline are sent later). Bzide never contacts Last.fm or ListenBrainz itself: to scrobble there, link your accounts in your server's web interface (in Navidrome, your user's Personal settings), and the server passes your plays on, from every app you use.\n\nOff, nothing about your listening is sent to the server from this iPhone: no plays, no \u{201C}now playing\u{201D}. The server's play counts, Recently Played, Most Played and Spin It Back stop updating from here; History on this iPhone still works.")
            }
            .themedRows(grouped: true)
            Section {
                NavigationLink {
                    DocumentView("USER-GUIDE", title: "Help")
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                NavigationLink {
                    DocumentView("PRIVACY", title: "Privacy")
                } label: {
                    Label("Privacy", systemImage: "hand.raised")
                }
            } footer: {
                Text("Help: how to use everything in Bzide. Privacy: what Bzide sends, to whom, and what it keeps on this iPhone.")
            }
            .themedRows(grouped: true)
            if account != nil {
                BackupSection(actions: backup)
            }
            Section {
                Button("Restore Default Settings", role: .destructive) { isConfirmingRestoreDefaults = true }
            } footer: {
                Text("Puts every setting back to how Bzide starts, with the online services off, and resets the Library layout, filters and visualizer. Your downloads, history (and how long it's kept), Wishlist, profile picture and lyrics timing fixes stay.")
            }
            .themedRows(grouped: true)
            if let debugPlayer {
                Section {
                    NavigationLink {
                        debugPlayer()
                    } label: {
                        Label("Debug Player", systemImage: "ladybug")
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("A bare player for testing playback. Only in builds installed from Xcode.")
                }
                .themedRows(grouped: true)
            }
        }
        .themedList(grouped: true)
        .readableWidth()
        .navigationTitle("Settings")
        .confirmationDialog("Sign out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { signOut() }
        } message: {
            Text("Playback stops. Your downloads and history stay unless you sign in to a different account.")
        }
        .confirmationDialog("Restore default settings?", isPresented: $isConfirmingRestoreDefaults, titleVisibility: .visible) {
            Button("Restore Defaults", role: .destructive) { restoreDefaults() }
        } message: {
            Text("Every setting goes back to how Bzide starts. Downloads, history, tagged radio songs and your profile picture stay.")
        }
        .confirmationDialog("Clear all play history?", isPresented: $isConfirmingClearHistory, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { history.clear() }
        }
        .confirmationDialog("Remove all downloads?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
            Button("Remove All Downloads", role: .destructive) { downloads.removeAll() }
        }
    }

    /// Where the profile picture comes from, then what's needed for that choice.
    /// The mix settings' explanation, in the rating style in use.
    private var mixesFooter: String {
        settings.settings.useSimplifiedRating
            ? "Include Meh Songs: off, Random Mix, Spin Off and Keep Spinning leave out songs you rated Meh. Songs you pick yourself always play.\n\nMix My Cuts plays the songs you rated Love or Like; with Include Favorites in My Cuts on, your favorites too (unless rated Meh)."
            : "Include 1–2 Star Songs: off, Random Mix, Spin Off and Keep Spinning leave out songs you rated 1 or 2 stars. Songs you pick yourself always play.\n\nMix My Cuts plays the songs you rated 3 stars or more; with Include Favorites in My Cuts on, your favorites too (unless rated 1 or 2 stars)."
    }

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
                ForEach(ThemeFamily.allCases, id: \.self) { family in
                    Section(family.title) {
                        ForEach(family.themes, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            if let palette = appearance.palette, let family = appearance.settings.theme.family,
               let current = appearance.settings.themeAccent {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Accent")
                        Spacer()
                        Text(current.title).foregroundStyle(.secondary)
                    }
                    SwatchGrid(
                        options: palette.accents,
                        color: { Color($0.color) },
                        title: \.title,
                        isSelected: { $0.id == current.id },
                        checkmark: Color(palette.base),
                        choose: { appearance.settings.setAccent($0.id, for: family) }
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
            if let family = appearance.settings.theme.family {
                Text("Colors from \(family.title) (\(family.source)).")
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

extension SettingsView {
    /// Refresh Library: the lists again now; done (✓) or why not.
    func refresh() {
        refreshState = .refreshing
        Task {
            do {
                try await refreshLibrary()
                refreshState = .done
            } catch {
                refreshState = .failed(error.localizedDescription)
            }
        }
    }
}

extension SettingsView {
    var dialGenresSummary: String {
        let genres = settings.settings.spinTheDial.genres
        switch genres.count {
        case 0: return "Any"
        case 1, 2: return genres.joined(separator: ", ")
        default: return "\(genres.count) genres"
        }
    }

    static func dialExplanation(_ mode: DialSettings.Mode) -> String {
        let how = switch mode {
        case .myTaste: "My Taste picks genres from what you listen to: your play history (recent plays count more) and favorites."
        case .myLibrary: "My Library picks genres from your library, not from what you've played."
        case .surpriseMe: "Surprise Me plays any working station, anywhere."
        case .somethingNew: "Something New picks genres outside your library and listening, and stations you haven't saved or dialed before."
        }
        return how + " Spin the Dial uses Radio Browser (Find Stations Online), which gets the genre and these settings for each spin, never your listening history. Next on a dialed station spins again."
    }
}

/// Spin the Dial's Genres: Radio Browser's most common genres to pick any
/// number from; none picked means any genre.
private struct DialGenresView: View {
    @State private var model: StationSearchModel
    @Binding var genres: [String]
    @State private var search = ""

    /// The model is made once, so the genres load once while the list is open.
    init(makeModel: () -> StationSearchModel, genres: Binding<[String]>) {
        _model = State(initialValue: makeModel())
        _genres = genres
    }

    var body: some View {
        LoadStateView(state: model.tags, retry: model.loadTags) { tags in
            let shown = search.isEmpty ? tags : tags.filter { $0.name.localizedStandardContains(search) }
            List {
                if search.isEmpty {
                    Section {
                        row("Any Genre", isChecked: genres.isEmpty) { genres = [] }
                    }
                    if !genres.isEmpty {
                        Section("Chosen") {
                            ForEach(genres, id: \.self) { genre in
                                row(genre, isChecked: true) { genres.removeAll { $0 == genre } }
                            }
                        }
                    }
                }
                Section {
                    ForEach(shown) { tag in
                        row(tag.name, count: tag.stationCount, isChecked: genres.contains(tag.name)) { toggle(tag.name) }
                    }
                }
            }
            .overlay {
                if shown.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Genres")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadTags() }
    }

    private func toggle(_ genre: String) {
        if genres.contains(genre) { genres.removeAll { $0 == genre } } else { genres.append(genre) }
    }

    private func row(_ title: String, count: Int? = nil, isChecked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if let count { Text(count.formatted()).foregroundStyle(.secondary).monospacedDigit() }
                if isChecked { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Chosen") }
            }
            .contentShape(.rect)
        }
    }
}

/// Weather (Live)'s Place field: looked up when the user presses Return or
/// leaves the field, with what Apple matched shown under it ("Springfield,
/// IL, United States"), or that nothing matched.
private struct LiveWeatherPlaceField: View {
    @Bindable var settings: StreamingSettingsModel
    @FocusState private var isEditing: Bool
    @State private var isLooking = false
    @State private var noMatch = false

    private var typed: String { settings.settings.liveWeatherCity }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Place", text: $settings.settings.liveWeatherCity, prompt: Text("City and state, or ZIP code"))
                .textContentType(.addressCityAndState)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isEditing)
                .onSubmit(lookUp)
                .onChange(of: isEditing) { _, editing in
                    if !editing { lookUp() }
                }
                .onChange(of: typed) {
                    noMatch = false
                }
            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var status: String? {
        if typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        if isLooking { return "Looking up…" }
        if noMatch { return "No match. Try adding the state or country, or a ZIP code." }
        if let match = settings.settings.liveWeatherPlace, match.matches(typed) { return "Found: \(match.name)" }
        return nil
    }

    private func lookUp() {
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            settings.settings.liveWeatherPlace = nil
            return
        }
        if let match = settings.settings.liveWeatherPlace, match.matches(query) { return }
        isLooking = true
        Task {
            let match = await LiveWeatherSource.lookUp(query)
            isLooking = false
            // Only if the field still says what was looked up.
            guard settings.settings.liveWeatherCity.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            settings.settings.liveWeatherPlace = match
            noMatch = match == nil
        }
    }
}

/// Settings > Wishlist: whether entries found in the library leave the
/// list, and when; and the long-press menu's Buy menu and its stores.
private struct WishlistSection: View {
    @Bindable var wishlist: Wishlist

    var body: some View {
        Section {
            Toggle("Remove Found Items", isOn: $wishlist.removesFound)
            if wishlist.removesFound {
                Picker("Remove", selection: $wishlist.removeFoundAfter) {
                    ForEach(FoundSongRemoval.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        } header: {
            Text("Wishlist")
        } footer: {
            Text("Songs, albums and artists on your Wishlist stay until you remove them. With this on, one that turns up in your library is removed from the list, counted from the day Bzide finds it there. Bzide checks your server when the app starts and when you open the list.")
        }
        .themedRows(grouped: true)
        Section {
            Toggle("Show Buy Menu", isOn: $wishlist.showsBuyMenu)
            if wishlist.showsBuyMenu {
                ForEach(Wishlist.stores, id: \.self) { store in
                    Toggle(store, isOn: shown(store))
                }
            }
        } footer: {
            Text("Long-press something on your Wishlist to buy it: Buy opens a search for it at the store you pick, in Safari or the store's app. Nothing is sent to a store until you tap it. Turn off the stores you don't want; with all of them off, there's no Buy menu.")
        }
        .themedRows(grouped: true)
    }

    private func shown(_ store: String) -> Binding<Bool> {
        Binding(
            get: { !wishlist.hiddenStores.contains(store) },
            set: { isOn in
                if isOn { wishlist.hiddenStores.remove(store) } else { wishlist.hiddenStores.insert(store) }
            }
        )
    }
}
