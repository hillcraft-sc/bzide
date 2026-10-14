import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct SleepTimerTests {
    /// Playback as the timer sees it.
    private final class Playback: SleepTimerTarget {
        var isPlaying = true
        var currentEntryID: QueueEntry.ID? = UUID()
        var position: TimeInterval = 0
        var duration: TimeInterval? = 200
        var outputVolume: Float = 1
        var pauses = 0

        func pause() {
            pauses += 1
            isPlaying = false
        }
    }

    /// The clock tests move forward.
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private func timer(_ playback: Playback, _ clock: Clock) -> SleepTimer {
        SleepTimer(target: playback, now: { clock.now }, ticksItself: false)
    }

    /// Moves time forward in steps, ticking, with the song's position following when playing.
    private func pass(_ seconds: TimeInterval, _ timer: SleepTimer, _ playback: Playback, _ clock: Clock, step: TimeInterval = 0.2) {
        var passed: TimeInterval = 0
        while passed < seconds - 0.0001 {
            clock.now += step
            if playback.isPlaying { playback.position += step }
            passed += step
            timer.tick()
        }
    }

    @Test func aTimedStopFadesThenPausesAndRestoresTheVolume() {
        let playback = Playback()
        let clock = Clock()
        let timer = timer(playback, clock)
        timer.start(minutes: 15)
        // Within a hair: dates round-trip through seconds since 2001.
        #expect(abs((timer.remaining(at: clock.now) ?? 0) - 15 * 60) < 0.001)
        pass(15 * 60 - 5, timer, playback, clock, step: 1)
        // Halfway through the fade.
        #expect(abs(playback.outputVolume - 0.5) < 0.11)
        #expect(playback.pauses == 0)
        pass(6, timer, playback, clock, step: 1)
        #expect(playback.pauses == 1)
        #expect(playback.outputVolume == 1)
        #expect(timer.mode == nil)
    }

    @Test func theVolumeIsUntouchedUntilTheFade() {
        let playback = Playback()
        let clock = Clock()
        let timer = timer(playback, clock)
        timer.start(minutes: 15)
        pass(60, timer, playback, clock, step: 1)
        #expect(playback.outputVolume == 1)
    }

    @Test func pausedEarlyItEndsQuietly() {
        let playback = Playback()
        let clock = Clock()
        let timer = timer(playback, clock)
        timer.start(minutes: 15)
        playback.isPlaying = false
        clock.now += 20 * 60
        timer.tick()
        #expect(playback.pauses == 0)
        #expect(timer.mode == nil)
        #expect(playback.outputVolume == 1)
    }

    @Test func turningItOffMidFadeRestoresTheVolume() {
        let playback = Playback()
        let clock = Clock()
        let timer = timer(playback, clock)
        timer.start(minutes: 15)
        pass(15 * 60 - 3, timer, playback, clock, step: 1)
        #expect(playback.outputVolume < 1)
        timer.cancel()
        #expect(playback.outputVolume == 1)
        #expect(timer.mode == nil)
        #expect(playback.pauses == 0)
    }

    @Test func choosingAnotherTimeRestartsIt() {
        let playback = Playback()
        let clock = Clock()
        let timer = timer(playback, clock)
        timer.start(minutes: 15)
        pass(15 * 60 - 3, timer, playback, clock, step: 1)
        timer.start(minutes: 30)
        #expect(playback.outputVolume == 1)
        #expect(abs((timer.remaining(at: clock.now) ?? 0) - 30 * 60) < 0.001)
    }

    @Test func endOfSongFadesTheSongOutAndStopsWhenItEnds() {
        let playback = Playback()
        let clock = Clock()
        let timer = timer(playback, clock)
        playback.position = 190
        timer.startEndOfSong()
        pass(8, timer, playback, clock)
        // Two seconds left: about half volume.
        #expect(abs(playback.outputVolume - 0.5) < 0.12)
        pass(1.8, timer, playback, clock)
        #expect(playback.outputVolume < 0.15)
        // The song ends and the next one begins, silently, and is paused at once.
        playback.currentEntryID = UUID()
        playback.position = 0
        timer.tick()
        #expect(playback.pauses == 1)
        #expect(playback.outputVolume == 1)
        #expect(timer.mode == nil)
    }

    @Test func skippingMovesEndOfSongToTheNewSong() {
        let playback = Playback()
        let clock = Clock()
        let timer = timer(playback, clock)
        playback.position = 30
        timer.startEndOfSong()
        pass(1, timer, playback, clock)
        // Skipped well before the end: keep playing, now waiting for this song.
        let next = UUID()
        playback.currentEntryID = next
        playback.position = 0
        timer.tick()
        #expect(playback.pauses == 0)
        #expect(timer.mode == .endOfSong)
        // That song ending stops the music.
        pass(199, timer, playback, clock)
        playback.currentEntryID = UUID()
        timer.tick()
        #expect(playback.pauses == 1)
    }

    @Test func theQueueRunningOutEndsIt() {
        let playback = Playback()
        let clock = Clock()
        let timer = timer(playback, clock)
        timer.startEndOfSong()
        playback.currentEntryID = nil
        playback.isPlaying = false
        timer.tick()
        #expect(timer.mode == nil)
        #expect(playback.pauses == 0)
    }

    @Test func aSongOfUnknownLengthIsntFaded() {
        let playback = Playback()
        playback.duration = nil
        let clock = Clock()
        let timer = timer(playback, clock)
        timer.startEndOfSong()
        pass(5, timer, playback, clock)
        #expect(playback.outputVolume == 1)
    }

    @Test func itSaysWhenTheMusicWillStop() {
        let playback = Playback()
        let clock = Clock()
        let timer = timer(playback, clock)
        #expect(timer.stopsIn(at: clock.now) == nil)
        timer.start(minutes: 15)
        #expect(abs((timer.stopsIn(at: clock.now) ?? 0) - 15 * 60) < 0.001)
        // End of Song: the time left in the song.
        playback.position = 150
        timer.startEndOfSong()
        #expect(timer.stopsIn(at: clock.now) == 50)
        playback.duration = nil
        #expect(timer.stopsIn(at: clock.now) == nil)
    }
}
