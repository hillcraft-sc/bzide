import Foundation
import Testing
@testable import NavidromeCore

struct SpectrumPeaksTests {
    private let frame: TimeInterval = 1.0 / 60

    private func run(_ peaks: inout SpectrumPeaks, seconds: Double, columns: [Float]) {
        for _ in 0..<Int(seconds * 60) {
            peaks.update(columns: columns, elapsed: frame)
        }
    }

    @Test func aDotJumpsUpWithItsColumn() {
        var peaks = SpectrumPeaks(count: 2)
        peaks.update(columns: [0.8, 0.2], elapsed: frame)
        #expect(peaks.peaks == [0.8, 0.2])
    }

    @Test func aDotHoldsThenFallsFasterAndFaster() {
        var peaks = SpectrumPeaks(count: 1)
        peaks.update(columns: [0.9], elapsed: frame)
        run(&peaks, seconds: 0.4, columns: [0])
        #expect(peaks.peaks[0] == 0.9)
        run(&peaks, seconds: 0.2, columns: [0])
        let afterFirstFall = peaks.peaks[0]
        #expect(afterFirstFall < 0.9)
        run(&peaks, seconds: 0.1, columns: [0])
        let secondDrop = afterFirstFall - peaks.peaks[0]
        #expect(secondDrop > 0.9 - afterFirstFall)
    }

    @Test func aFallingDotLandsOnItsColumn() {
        var peaks = SpectrumPeaks(count: 1)
        peaks.update(columns: [1], elapsed: frame)
        run(&peaks, seconds: 3, columns: [0.3])
        #expect(peaks.peaks[0] == 0.3)
    }

    @Test func aRisingColumnCatchesItsFallingDot() {
        var peaks = SpectrumPeaks(count: 1)
        peaks.update(columns: [0.6], elapsed: frame)
        run(&peaks, seconds: 0.8, columns: [0])
        peaks.update(columns: [0.7], elapsed: frame)
        #expect(peaks.peaks[0] == 0.7)
        // And holds again from there.
        run(&peaks, seconds: 0.4, columns: [0])
        #expect(peaks.peaks[0] == 0.7)
    }

    @Test func aNewColumnCountStartsAgain() {
        var peaks = SpectrumPeaks(count: 2)
        peaks.update(columns: [0.5, 0.5], elapsed: frame)
        peaks.update(columns: [0.1, 0.1, 0.1], elapsed: frame)
        #expect(peaks.peaks == [0.1, 0.1, 0.1])
    }

    @Test func columnsTakeTheLoudestOfTheirGroup() {
        let levels: [Float] = [0.1, 0.4, 0.3, 0.2, 0.9, 0.5]
        #expect(SpectrumPeaks.columns(from: levels, count: 3) == [0.4, 0.3, 0.9])
        #expect(SpectrumPeaks.columns(from: levels, count: 6) == levels)
    }

    @Test func columnsWithFewerLevelsOrNoneStillFill() {
        #expect(SpectrumPeaks.columns(from: [0.2, 0.8], count: 4) == [0.2, 0.2, 0.8, 0.8])
        #expect(SpectrumPeaks.columns(from: [], count: 3) == [0, 0, 0])
    }
}
