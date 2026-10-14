import Foundation

/// What the current song is actually playing as: its format, bitrate and
/// where it comes from. Shown beside the playback status.
public struct PlaybackQuality: Sendable, Equatable {
    /// "FLAC", "MP3"... `nil` when the server didn't say.
    public var format: String?
    /// Kbps; `nil` when unknown.
    public var bitRate: Int?
    /// The server converted it (to MP3 at a lower bitrate) rather than sending the original.
    public var isConverted: Bool
    /// Playing from a downloaded file rather than streaming.
    public var isDownloaded: Bool
    /// The volume normalization applied, in decibels; `nil` for none.
    public var normalization: Double?

    public init(format: String?, bitRate: Int?, isConverted: Bool = false, isDownloaded: Bool = false) {
        self.format = format?.uppercased()
        self.bitRate = bitRate
        self.isConverted = isConverted
        self.isDownloaded = isDownloaded
    }

    /// e.g. "FLAC · 1,411 kbps", "MP3 · 192 kbps · Converted", "FLAC · Downloaded".
    public var label: String {
        var parts: [String] = []
        if let format { parts.append(format) }
        if let bitRate { parts.append("\(bitRate.formatted()) kbps") }
        if isConverted { parts.append("Converted") }
        if isDownloaded { parts.append("Downloaded") }
        if let normalization { parts.append(Self.decibels(normalization)) }
        return parts.isEmpty ? "Unknown quality" : parts.joined(separator: " · ")
    }

    /// e.g. "−4.2 dB", "+1.5 dB", "0 dB".
    static func decibels(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "0 dB" }
        let magnitude = abs(rounded).formatted(.number.precision(.fractionLength(1)))
        return "\(rounded < 0 ? "\u{2212}" : "+")\(magnitude) dB"
    }

    /// The original, as the server describes it.
    static func original(_ song: Song, downloaded: Bool = false) -> PlaybackQuality {
        PlaybackQuality(format: song.suffix, bitRate: song.bitRate, isDownloaded: downloaded)
    }

    /// Streamed with a bitrate cap. The server only converts what's above the
    /// cap or not already MP3, so a small MP3 is still the original.
    static func streamed(_ song: Song, cap: Int?) -> PlaybackQuality {
        guard let cap else { return .original(song) }
        let alreadyFits = song.suffix?.lowercased() == DownloadManager.convertedFormat && (song.bitRate ?? .max) <= cap
        return alreadyFits ? .original(song) : PlaybackQuality(format: DownloadManager.convertedFormat, bitRate: cap, isConverted: true)
    }
}
