import Foundation
import Observation

/// What the sleep timer needs from playback (the engine, or a fake in tests).
@MainActor
public protocol SleepTimerTarget: AnyObject {
    var isPlaying: Bool { get }
    var currentEntryID: QueueEntry.ID? { get }
    /// Seconds into the current song, updated a few times a second.
    var position: TimeInterval { get }
    var duration: TimeInterval? { get }
    /// 0...1, 1 normal: lowered to fade out.
    var outputVolume: Float { get set }
    func pause()
}

/// Stops the music after a while, for falling asleep to it: after a set
/// number of minutes, or at the end of the current song. The music fades out
/// rather than cutting off, then pauses, and the volume goes back to normal so
/// the next Play isn't silent.
///
/// It counts to a fixed time on the clock, so it stays right with the screen
/// locked. Pausing early doesn't stop it; it just ends quietly. It isn't
/// saved, so a forgotten timer can't stop the music another day.
@MainActor
@Observable
public final class SleepTimer {
    public enum Mode: Equatable, Sendable {
        case minutes(Int)
        case endOfSong
    }

    /// The minute choices offered.
    public static let minuteChoices = [15, 30, 45, 60]
    /// How long the fade at the end of a timed stop takes.
    public static let fade: TimeInterval = 10
    /// How long the fade at the end of a song takes.
    public static let songFade: TimeInterval = 4
    /// A song change this close to the song's end is the song ending, not a skip.
    static let endTolerance: TimeInterval = 2.5

    /// The running timer, or `nil` when off.
    public private(set) var mode: Mode?
    /// When a timed stop happens.
    public private(set) var deadline: Date?

    @ObservationIgnored private let target: SleepTimerTarget
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let ticksItself: Bool
    @ObservationIgnored private var ticking: Task<Void, Never>?
    /// For End of Song: the song it's waiting for, and how close to its end it
    /// was last seen (to tell it ending from a skip).
    @ObservationIgnored private var song: QueueEntry.ID?
    @ObservationIgnored private var lastLeft: TimeInterval?
    /// The position last seen and when, to estimate it smoothly between the
    /// engine's updates for a fade without steps.
    @ObservationIgnored private var seen: (position: TimeInterval, at: Date)?

    /// `ticksItself` runs the timer on its own (the app); tests call `tick` instead.
    public init(target: SleepTimerTarget, now: @escaping () -> Date = { .now }, ticksItself: Bool = true) {
        self.target = target
        self.now = now
        self.ticksItself = ticksItself
    }

    public func start(minutes: Int) {
        begin(.minutes(minutes))
        deadline = now().addingTimeInterval(TimeInterval(minutes) * 60)
    }

    public func startEndOfSong() {
        begin(.endOfSong)
        deadline = nil
        song = target.currentEntryID
    }

    public func cancel() {
        finish(pausing: false)
    }

    /// Time left on a timed stop, or `nil`.
    public func remaining(at date: Date) -> TimeInterval? {
        deadline.map { max($0.timeIntervalSince(date), 0) }
    }

    /// How long until the music stops, for showing: the time left on a timed
    /// stop, or in the song for End of Song. `nil` when off, or when the
    /// song's length isn't known.
    public func stopsIn(at date: Date) -> TimeInterval? {
        switch mode {
        case nil: nil
        case .minutes: remaining(at: date)
        case .endOfSong: target.duration.map { max($0 - target.position, 0) }
        }
    }

    /// Checks the timer, fading and stopping as due. The app calls this about
    /// five times a second while a timer runs.
    public func tick() {
        guard let mode else { return }
        let date = now()
        switch mode {
        case .minutes:
            guard let left = remaining(at: date) else { return }
            if left <= 0 {
                finish(pausing: true)
            } else if left < Self.fade, target.isPlaying {
                setVolume(Float(left / Self.fade))
            }
        case .endOfSong:
            tickEndOfSong(at: date)
        }
    }

    private func tickEndOfSong(at date: Date) {
        let current = target.currentEntryID
        if current != song {
            // The song ended (or the queue did): stop. A skip just moves on to wait
            // for the new song instead.
            if current == nil || (lastLeft ?? .infinity) <= Self.endTolerance {
                finish(pausing: current != nil)
                return
            }
            song = current
            lastLeft = nil
            seen = nil
            setVolume(1)
        }
        guard let duration = target.duration, duration > 0 else { return }
        let left = duration - estimatedPosition(at: date)
        lastLeft = left
        if target.isPlaying, left < Self.songFade {
            setVolume(Float(max(left, 0) / Self.songFade))
        }
    }

    private func estimatedPosition(at date: Date) -> TimeInterval {
        let reported = target.position
        if seen?.position != reported {
            seen = (reported, date)
        }
        guard target.isPlaying, let seen else { return reported }
        return reported + date.timeIntervalSince(seen.at)
    }

    private func begin(_ mode: Mode) {
        // A new choice replaces a running timer, fade and all.
        setVolume(1)
        self.mode = mode
        song = nil
        lastLeft = nil
        seen = nil
        guard ticksItself, ticking == nil else { return }
        ticking = Task { [weak self] in
            while let self, self.mode != nil {
                self.tick()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func finish(pausing: Bool) {
        if pausing, target.isPlaying { target.pause() }
        setVolume(1)
        mode = nil
        deadline = nil
        song = nil
        lastLeft = nil
        seen = nil
        ticking?.cancel()
        ticking = nil
    }

    private func setVolume(_ volume: Float) {
        let clamped = min(max(volume, 0), 1)
        if target.outputVolume != clamped { target.outputVolume = clamped }
    }
}

extension PlaybackEngine: SleepTimerTarget {
    public var isPlaying: Bool { status == .playing }
    public var currentEntryID: QueueEntry.ID? { queue.current?.id }
}
