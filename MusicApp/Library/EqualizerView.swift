import AVFoundation
import NavidromeCore
import SwiftUI

/// Settings > Equalizer, and Now Playing's ••• > Equalizer: on or off, a
/// preset, and the ten bands. Moving a band makes the settings your own
/// (Custom). Changes are heard at once, gliding in without a click.
struct EqualizerView: View {
    @Bindable var equalizer: EqualizerModel
    /// To say whether it reaches what's playing.
    let engine: PlaybackEngine

    var body: some View {
        Form {
            Section {
                Toggle("Equalizer", isOn: $equalizer.settings.isOn)
                if equalizer.settings.isOn, engine.status == .playing {
                    EqualizerReachRow(equalizer: equalizer)
                }
                Picker("Preset", selection: $equalizer.settings.preset) {
                    ForEach(EqualizerPreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .disabled(!equalizer.settings.isOn)
            } footer: {
                Text("Applies to songs played on this iPhone, its headphones and Bluetooth. Radio stations and AirPlay can't be equalized: their audio doesn't pass through the app. Boosting a band makes the music quieter overall by the same amount, so loud songs don't distort.")
            }
            .themedRows(grouped: true)

            Section {
                ForEach(EqualizerBands.frequencies.indices, id: \.self) { band in
                    BandRow(
                        frequency: EqualizerBands.frequencies[band],
                        gain: equalizer.settings.gains[band],
                        setGain: { equalizer.setGain($0, band: band) }
                    )
                }
                if equalizer.settings.preset == .custom {
                    Button("Reset to Flat", role: .destructive) { equalizer.resetCustom() }
                }
            } header: {
                Text("Bands")
            } footer: {
                Text("Moving a band starts your own settings (Custom) from the preset's.")
            }
            .disabled(!equalizer.settings.isOn)
            .themedRows(grouped: true)
        }
        .themedList(grouped: true)
        .navigationTitle("Equalizer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "1 kHz", a slider from −12 to +12 dB in half steps, and "+3 dB".
private struct BandRow: View {
    let frequency: Double
    let gain: Double
    /// Main-actor isolated, so SwiftUI's binding can hold it safely.
    let setGain: @MainActor (Double) -> Void

    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 12) {
            Text(EqualizerBands.label(frequency))
                .font(.subheadline.monospacedDigit())
                .frame(width: labelWidth, alignment: .leading)
            Slider(
                value: Binding(get: { gain }, set: setGain),
                in: EqualizerBands.range,
                step: 0.5
            )
            Text(Self.format(gain))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)
        }
        // One element: "1 kHz, plus 3 decibels", adjusted by swiping up or down.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EqualizerBands.label(frequency))
        .accessibilityValue(Self.spoken(gain))
        .accessibilityAdjustableAction { direction in
            setGain(gain + (direction == .increment ? 1 : -1))
        }
    }

    static func format(_ gain: Double) -> String {
        let amount = abs(gain).formatted(.number.precision(.fractionLength(0...1)))
        return gain == 0 ? "0 dB" : "\(gain > 0 ? "+" : "−")\(amount) dB"
    }

    static func spoken(_ gain: Double) -> String {
        let amount = abs(gain).formatted(.number.precision(.fractionLength(0...1)))
        return gain == 0 ? "0 decibels" : "\(gain > 0 ? "plus" : "minus") \(amount) decibels"
    }
}

/// Whether the equalizer reaches what's playing, asked once a second: it does
/// when a song's audio tap is processing it, never for radio or over AirPlay.
enum EqualizerReach {
    @MainActor
    static func isApplied(_ equalizer: EqualizerModel) -> Bool {
        guard !AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .airPlay }) else { return false }
        return equalizer.isReachingPlayback
    }
}

private struct EqualizerReachRow: View {
    let equalizer: EqualizerModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if EqualizerReach.isApplied(equalizer) {
                Label("Applied to what's playing", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label("Can't be applied to what's playing (radio or AirPlay)", systemImage: "slash.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "EQ" in Now Playing's status line while the equalizer is on and heard;
/// "EQ unavailable" while it's on but what's playing can't be equalized.
struct EqualizerBadge: View {
    let equalizer: EqualizerModel
    let engine: PlaybackEngine

    var body: some View {
        if equalizer.settings.isOn, engine.status == .playing {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let applied = EqualizerReach.isApplied(equalizer)
                Text(applied ? "EQ" : "EQ unavailable")
                    .foregroundStyle(applied ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityLabel(applied ? "Equalizer on" : "Equalizer can't be applied to this")
            }
        }
    }
}
