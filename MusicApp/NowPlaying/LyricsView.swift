import NavidromeCore
import SwiftUI

/// Full-screen lyrics, after Apple Music's: big bold lines over a blurred copy
/// of the cover. With synced lyrics the current line is bright, its words
/// lighting up as they're sung, and the view follows along; the other lines
/// are dimmed and softened. Tap a line to jump there. Scrolling by hand pauses
/// the following for a few seconds. Unsynced lyrics just scroll; with none, a
/// message says so. `LyricsModel` finds them; the title and controls are at
/// the bottom.
struct LyricsView: View {
    let library: Library

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    /// Unsynced lyrics' size, following the user's text size.
    @ScaledMetric(relativeTo: .title) private var plainSize: CGFloat = 26
    @State private var clock = LyricsClock()
    @State private var cover: UIImage?
    /// Until when hand scrolling has stopped the view following the song.
    @State private var followingPausedUntil: Date = .distantPast
    /// "Wrong lyrics?" found no other match on LRCLIB.
    @State private var isShowingNoMore = false
    /// "Wrong lyrics?" couldn't reach LRCLIB.
    @State private var isShowingLookupFailed = false

    private var engine: PlaybackEngine { library.engine }
    private var model: LyricsModel { library.lyrics }
    private var song: Song? { engine.queue.current?.song }
    private var onlineAllowed: Bool { library.settings.settings.findLyricsOnline }
    /// Settings > Lyrics > Wrong Lyrics Button.
    private var usesChoices: Bool { onlineAllowed && library.settings.settings.wrongLyricsButton }

    /// How long hand scrolling stops the view following the song.
    private static let followingPause: TimeInterval = 3

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top) { topBar }
            .safeAreaInset(edge: .bottom) { bottomBar }
            // Behind, so the cover (scaled to fill) can't widen the layout.
            .background { background }
            .preferredColorScheme(.dark)
            // It covers Now Playing: the app's messages show here.
            .appMessages(library)
            .alert("No Other Lyrics", isPresented: $isShowingNoMore) {
                Button("Don't Use LRCLIB for This Song") { Task { await model.turnDownOnline() } }
                if song.flatMap(model.choice(for:)) != nil {
                    Button("Back to the Best Match") { Task { await model.useBestMatch() } }
                }
                Button("Keep These", role: .cancel) {}
            } message: {
                Text("LRCLIB has no other version of this song's lyrics.")
            }
            .alert("Couldn't Reach LRCLIB", isPresented: $isShowingLookupFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your connection and try again.")
            }
        .task(id: "\(song?.id ?? "")|\(onlineAllowed)|\(usesChoices)") {
            await model.load(song, onlineAllowed: onlineAllowed, usesChoices: usesChoices)
        }
        .task(id: song?.coverArtID) {
            cover = nil
            guard let coverArtID = song?.coverArtID else { return }
            let loaded = await library.artwork.image(for: coverArtID, pixels: 600)
            // The song changed while it loaded: this cover is for the old one.
            guard !Task.isCancelled else { return }
            cover = loaded
        }
    }

    // MARK: - Parts

    /// The cover, blurred and darkened to fill the screen; a dark gradient without one.
    private var background: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(white: 0.18), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 60)
                        .overlay(.black.opacity(0.45))
                        .clipped()
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: cover != nil)
    }

    private var topBar: some View {
        HStack {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.15), in: .circle)
            Spacer()
            if let song, showsLRCLIBMenu(for: song) {
                lrclibMenu(song)
            }
            if case .loaded(let lyrics) = model.state, lyrics.isSynced, let songID = song?.id {
                timingMenu(songID)
            }
        }
        .tint(.white)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// For lyrics from LRCLIB, or a song whose LRCLIB lyrics the user changed.
    private func showsLRCLIBMenu(for song: Song) -> Bool {
        guard usesChoices else { return false }
        if case .loaded(let lyrics) = model.state, lyrics.source == .lrclib { return true }
        return model.choice(for: song) != nil
    }

    /// "Wrong lyrics?": LRCLIB's next match, or none from LRCLIB; and back
    /// to its best match after a change. Remembered for the song.
    private func lrclibMenu(_ song: Song) -> some View {
        let isFromLRCLIB = if case .loaded(let lyrics) = model.state { lyrics.source == .lrclib } else { false }
        let choice = model.choice(for: song)
        // Another match than LRCLIB's best is showing: in the accent, so it's
        // clear the lyrics were changed.
        let isChangedVersion = if case .lrclib(let id) = choice, case .loaded(let lyrics) = model.state {
            lyrics.lrclibID == id
        } else {
            false
        }
        return Menu {
            if isFromLRCLIB {
                Section("Lyrics for another version of the song?") {
                    Button("Try LRCLIB's Next Match", systemImage: "arrow.trianglehead.2.clockwise") { tryAnother() }
                    Button("Don't Use LRCLIB for This Song", systemImage: "nosign") { Task { await model.turnDownOnline() } }
                }
            }
            if choice != nil {
                Button("Back to LRCLIB's Best Match", systemImage: "arrow.counterclockwise") { Task { await model.useBestMatch() } }
            }
        } label: {
            HStack(spacing: 4) {
                if model.isTryingAnother {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    // A different symbol too, not just the color, once changed.
                    Image(systemName: isChangedVersion ? "text.badge.checkmark" : "text.badge.xmark")
                }
                Text(isFromLRCLIB ? "Wrong lyrics?" : "LRCLIB off").font(.footnote.weight(.semibold))
            }
            .foregroundStyle(isChangedVersion ? accent ?? .accentColor : .white)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(.white.opacity(0.15), in: .capsule)
        }
        .disabled(model.isTryingAnother)
        .accessibilityLabel("Wrong Lyrics")
        .accessibilityValue(isChangedVersion ? "Showing another match" : "")
    }

    private func tryAnother() {
        Task {
            switch await model.tryAnother() {
            case .shown: break
            case .noMore: isShowingNoMore = true
            case .failed: isShowingLookupFailed = true
            }
        }
    }

    /// Seconds earlier to show this song's lyrics (negative: later).
    private var offset: TimeInterval {
        song.map { library.lyricsTiming.offset(for: $0.id) } ?? 0
    }

    /// Nudges the lyrics earlier or later when they run behind or ahead of
    /// the singing; remembered for the song.
    private func timingMenu(_ songID: String) -> some View {
        let timing = library.lyricsTiming
        let current = timing.offset(for: songID)
        return Menu {
            Section("Lyrics out of step with the singing?") {
                Button("Show Earlier (\u{2212}\(LyricsTiming.step.formatted()) s)", systemImage: "backward") { timing.earlier(songID) }
                Button("Show Later (+\(LyricsTiming.step.formatted()) s)", systemImage: "forward") { timing.later(songID) }
            }
            if current != 0 {
                Button("Reset Timing", systemImage: "arrow.counterclockwise") { timing.reset(songID) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                if let shift = LyricsTiming.describe(current) {
                    Text(shift).font(.footnote.weight(.semibold))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(.white.opacity(0.15), in: .capsule)
        }
        .accessibilityLabel("Lyrics Timing")
        .accessibilityValue(LyricsTiming.describe(current) ?? "Unchanged")
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            OverlayTitle(engine: engine)
            OverlayTransport(engine: engine)
        }
        .tint(.white)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let lyrics) where lyrics.isSynced:
            syncedLyrics(lyrics)
        case .loaded(let lyrics):
            plainLyrics(lyrics)
        case .instrumental:
            message("Instrumental", "This song has no words.", symbol: "music.note")
        case .none(let note):
            message("No Lyrics", ["There are no lyrics for this song.", note].compactMap(\.self).joined(separator: "\n\n"), symbol: "quote.bubble")
        case .radio:
            message("No Lyrics", "Lyrics aren't available for radio.", symbol: "headphones.sensor.tag.radiowaves.left.and.right") // dot.radiowaves.left.and.right
        case .failed(let text):
            message("Couldn't Load Lyrics", text, symbol: "wifi.exclamationmark")
        }
    }

    private func message(_ title: String, _ description: String, symbol: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(description))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Synced

    private func syncedLyrics(_ lyrics: Lyrics) -> some View {
        // The current line is worked out ten times a second; only that line
        // redraws every frame, to light its words.
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let time = clock.time(engine: engine, at: timeline.date) + offset
            let current = lyrics.lineIndex(at: time)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(lyrics.lines) { line in
                            LyricsLineView(line: line, current: current, clock: clock, engine: engine, offset: offset)
                                .id(line.id)
                                .contentShape(.rect)
                                .onTapGesture { jump(to: line) }
                                // VoiceOver: each line a button that jumps there.
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(line.text)
                                .accessibilityHidden(line.isBreak)
                                .accessibilityAddTraits(line.start == nil ? [] : .isButton)
                                .accessibilityHint(line.start == nil ? "" : "Jumps the song to this line")
                                .accessibilityAction { jump(to: line) }
                        }
                        credit(lyrics)
                    }
                    .padding(.horizontal, 28)
                    // Room to bring the first and last lines to the reading spot.
                    .padding(.vertical, 240)
                }
                .scrollIndicators(.hidden)
                .mask(fadedEdges)
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting || phase == .decelerating {
                        followingPausedUntil = .now + Self.followingPause
                    }
                }
                .onChange(of: current, initial: true) { _, line in
                    follow(line, proxy: proxy, animated: true)
                }
                .onChange(of: timeline.date >= followingPausedUntil) { _, isFollowing in
                    // Back from hand scrolling: return to where the song is.
                    if isFollowing { follow(current, proxy: proxy, animated: true) }
                }
            }
        }
    }

    /// Where the line shows, with the timing fix.
    private func jump(to line: Lyrics.Line) {
        guard let start = line.start else { return }
        engine.seek(to: max(start - offset, 0))
        followingPausedUntil = .distantPast
    }

    private func follow(_ line: Int?, proxy: ScrollViewProxy, animated: Bool) {
        guard Date.now >= followingPausedUntil else { return }
        // Before the first line, keep the top in view.
        let target = line ?? 0
        // With Reduce Motion, it moves without the spring.
        withAnimation(animated && !reduceMotion ? .spring(duration: 0.6, bounce: 0.1) : nil) {
            proxy.scrollTo(target, anchor: UnitPoint(x: 0, y: 0.3))
        }
    }

    // MARK: - Unsynced

    private func plainLyrics(_ lyrics: Lyrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("These lyrics aren't synced to the music.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(contrast == .increased ? 0.85 : 0.6))
                    .padding(.bottom, 8)
                ForEach(lyrics.lines) { line in
                    if line.isBreak {
                        Spacer().frame(height: 14)
                    } else {
                        Text(line.text)
                            .font(.system(size: plainSize, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                credit(lyrics)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .scrollIndicators(.hidden)
        .mask(fadedEdges)
    }

    @ViewBuilder
    private func credit(_ lyrics: Lyrics) -> some View {
        if lyrics.source == .lrclib {
            Text("Lyrics from LRCLIB")
                .font(.footnote)
                .foregroundStyle(.white.opacity(contrast == .increased ? 0.8 : 0.5))
                .padding(.top, 24)
        }
    }

    /// Lines fade out toward the top and bottom bars instead of being cut off.
    private var fadedEdges: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.9),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// One line of synced lyrics. The current one is bright, and redraws every
/// frame to light each word as it's sung, letter by letter; the rest are dim
/// and softened, more so further away.
private struct LyricsLineView: View {
    let line: Lyrics.Line
    let current: Int?
    let clock: LyricsClock
    let engine: PlaybackEngine
    /// The song's timing fix: seconds earlier to show its lyrics.
    let offset: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    /// Following the user's text size.
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 30

    private var isCurrent: Bool { line.id == current }
    private var distance: Int { abs(line.id - (current ?? -1)) }

    var body: some View {
        Group {
            if line.isBreak {
                breakDots
            } else if isCurrent {
                TimelineView(.animation) { timeline in
                    Text(Self.lit(line, at: clock.time(engine: engine, at: timeline.date) + offset))
                }
            } else {
                // Brighter, and never blurred, with Increase Contrast.
                Text(line.text).foregroundStyle(.white.opacity(contrast == .increased ? 0.6 : 0.35))
            }
        }
        .font(.system(size: size, weight: .bold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(isCurrent || reduceMotion ? 1 : 0.96, anchor: .leading)
        .blur(radius: isCurrent || contrast == .increased ? 0 : min(Double(distance), 3) * 0.6)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isCurrent)
    }

    /// An instrumental break: three dots, breathing while it's the current line.
    @ViewBuilder
    private var breakDots: some View {
        if isCurrent {
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                // Still with Reduce Motion: no breathing.
                let pulse = reduceMotion ? 1 : (sin(timeline.date.timeIntervalSinceReferenceDate * 3) + 1) / 2
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().frame(width: 12, height: 12)
                    }
                }
                .foregroundStyle(.white.opacity(0.5 + 0.4 * pulse))
                .scaleEffect(0.9 + 0.15 * pulse, anchor: .leading)
            }
        } else {
            // Kept small so a break doesn't leave a gap.
            Color.clear.frame(height: 4)
        }
    }

    /// The line with each letter as bright as how far the singing has got
    /// through its word.
    static func lit(_ line: Lyrics.Line, at time: TimeInterval) -> AttributedString {
        guard !line.words.isEmpty else {
            var whole = AttributedString(line.text)
            whole.foregroundColor = .white
            return whole
        }
        var result = AttributedString()
        for (index, word) in line.words.enumerated() {
            let progress = Lyrics.progress(of: word, at: time)
            let letters = Array(word.text)
            for (position, letter) in letters.enumerated() {
                let lit = min(max(progress * Double(letters.count) - Double(position), 0), 1)
                var piece = AttributedString(String(letter))
                // Brighter than the other lines even before it's sung.
                piece.foregroundColor = .white.opacity(0.6 + 0.4 * lit)
                result += piece
            }
            if index < line.words.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }
}

/// Song time that runs smoothly between the engine's position updates (a few
/// a second) and follows seeks, shared by the parts of the lyrics screen that
/// redraw at different rates.
@MainActor
final class LyricsClock {
    private var clock = SongClock()
    private var lastFrame: Date?

    func time(engine: PlaybackEngine, at date: Date) -> TimeInterval {
        // Two timelines ask; only time that's passed since the last ask counts.
        let elapsed = lastFrame.map { max(date.timeIntervalSince($0), 0) } ?? 0
        if lastFrame.map({ date > $0 }) ?? true { lastFrame = date }
        _ = clock.update(
            entryID: engine.queue.current?.id, position: engine.position,
            isPlaying: engine.status == .playing, elapsed: min(elapsed, 0.1)
        )
        return clock.songTime
    }
}
