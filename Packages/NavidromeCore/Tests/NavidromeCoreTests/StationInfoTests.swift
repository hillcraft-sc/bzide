import Foundation
import Testing
@testable import NavidromeCore

struct StreamHeadersTests {
    @Test func icecastAndShoutcastHeadersAreRead() {
        let headers = StreamHeaders(headers: [
            "Content-Type": "audio/mpeg", "Server": "Icecast 2.4.4", "icy-br": "128",
            "ice-audio-info": "channels=2;samplerate=44100;bitrate=128",
            "icy-description": "Commercial-free rock, all day", "icy-genre": "Rock",
            "icy-name": "Night Waves (128k mp3)", "icy-url": "https://waves.example.com", "icy-pub": "1",
        ])
        #expect(headers == StreamHeaders(
            name: "Night Waves (128k mp3)", description: "Commercial-free rock, all day", genre: "Rock",
            website: "https://waves.example.com", bitrate: 128, sampleRate: 44100, contentType: "audio/mpeg", server: "Icecast 2.4.4"
        ))
        #expect(headers.format == "MP3")
    }

    @Test func missingAndOddValuesAreLeftOut() {
        let headers = StreamHeaders(headers: ["ICY-BR": "64,64", "icy-name": "  ", "content-type": "audio/aacp; charset=x"])
        #expect(headers.bitrate == 64)
        #expect(headers.name == nil)
        #expect(headers.format == "AAC")
        #expect(StreamHeaders(headers: ["content-type": "text/html"]).format == nil)
    }
}

struct StationInfoSectionsTests {
    private static let stream = URL(string: "https://stream.example.com/waves")!

    private static func listing() throws -> RadioBrowserStation {
        let json = #"{"stationuuid":"u-1","name":"Night Waves","url":"https://stream.example.com/waves","homepage":"https://waves.example.com","countrycode":"US","state":"Ohio","language":"english,spanish","tags":"jazz,lounge","codec":"MP3","bitrate":128,"votes":1234,"clickcount":56,"lastcheckok":1,"hls":0}"#
        return try JSONDecoder().decode(RadioBrowserStation.self, from: Data(json.utf8))
    }

    private static func values(_ sections: [InfoSection]) -> [String: String] {
        Dictionary(sections.flatMap { section in section.rows.map { ("\(section.title)/\($0.label)", $0.value) } }, uniquingKeysWith: { first, _ in first })
    }

    @Test func radioBrowserListingsCarryMoreForStationInfo() throws {
        let listing = try Self.listing()
        #expect(listing.state == "Ohio")
        #expect(listing.language == "english,spanish")
        #expect(listing.votes == 1234)
        #expect(listing.clickCount == 56)
        #expect(listing.lastCheckOK == true)
        #expect(!listing.isHLS)
    }

    @Test func everythingKnownIsShown() throws {
        let monday = Date(timeIntervalSince1970: 1_800_000_000)
        let subject = StationInfoSubject(name: "Night Waves", stream: Self.stream, savedIn: .server, firstSeen: monday, announced: "Radiohead - Karma Police")
        let headers = StreamHeaders(description: "Commercial-free jazz", sampleRate: 44100, server: "Icecast 2.4.4")
        let values = Self.values(StationInfo.sections(for: subject, listing: try Self.listing(), headers: headers, countryName: { $0 == "US" ? "United States" : $0 }))
        #expect(values["On Air/Now Playing"] == "Radiohead - Karma Police")
        #expect(values["Station/About"] == "Commercial-free jazz")
        #expect(values["Station/Country"] == "United States")
        #expect(values["Station/Region"] == "Ohio")
        #expect(values["Station/Language"] == "English, Spanish")
        #expect(values["Station/Genres"] == "jazz, lounge")
        #expect(values["Station/Homepage"] == "https://waves.example.com")
        #expect(values["Stream/Format"] == "MP3")
        #expect(values["Stream/Bitrate"] == "128 kbps")
        #expect(values["Stream/Sample Rate"] == "44.1 kHz")
        #expect(values["Stream/Address"] == Self.stream.absoluteString)
        #expect(values["Stream/Server"] == "Icecast 2.4.4")
        #expect(values["Radio Browser/Last Check"] == "Working")
        #expect(values["In Bzide/Saved"] == "On your server")
        #expect(values["In Bzide/Added"] != nil)
    }

    @Test func withLittleKnownOnlyThatShows() {
        let subject = StationInfoSubject(name: "Hand Added", stream: Self.stream)
        let sections = StationInfo.sections(for: subject, listing: nil, headers: nil)
        #expect(sections.map(\.title) == ["Stream", "In Bzide"])
        let values = Self.values(sections)
        #expect(values["In Bzide/Saved"] == "Not saved")
        #expect(values["Stream/Format"] == nil)
        // The stream's own description fills in for Radio Browser.
        let described = Self.values(StationInfo.sections(for: subject, listing: nil, headers: StreamHeaders(genre: "Talk", bitrate: 64, contentType: "audio/aac")))
        #expect(described["Station/Genres"] == "Talk")
        #expect(described["Stream/Format"] == "AAC")
        #expect(described["Stream/Bitrate"] == "64 kbps")
    }
}

struct PlayingStationTests {
    private static let stream = URL(string: "https://stream.example.com/waves")!

    @Test func aSavedStationIsFoundByItsEntry() {
        var saved = RadioStation(id: "rs-1", name: "Night Waves", streamURL: Self.stream)
        saved.firstSeen = Date(timeIntervalSince1970: 1)
        let song = Song(station: saved, stream: Self.stream)
        let subject = StationInfoSubject.playing(song, saved: [saved], tuned: nil, announced: "A - B")
        #expect(subject?.savedIn == .server)
        #expect(subject?.firstSeen == Date(timeIntervalSince1970: 1))
        #expect(subject?.announced == "A - B")
    }

    @Test func aDialedStationUsesWhatTheDialFound() {
        let tuned = RadioBrowserStation(id: "j1", name: "Jazz", streamURL: Self.stream, homePageURL: URL(string: "https://jazz.example.com"), countryCode: "US")
        let song = Song(station: SpinTheDialModel.dialStation(tuned), stream: Self.stream)
        let unsaved = StationInfoSubject.playing(song, saved: [], tuned: tuned, announced: nil)
        #expect(unsaved?.savedIn == nil)
        #expect(unsaved?.details?.countryCode == "US")
        #expect(unsaved?.homePage?.absoluteString == "https://jazz.example.com")
        // Saved already (by its stream): saved, with the dial's details.
        let saved = RadioStation(id: "phone:1", name: "My Jazz", streamURL: Self.stream)
        let known = StationInfoSubject.playing(song, saved: [saved], tuned: tuned, announced: nil)
        #expect(known?.savedIn == .phone)
        #expect(known?.name == "My Jazz")
        #expect(known?.details?.countryCode == "US")
    }

    @Test func otherwiseWhatTheEntryKept() {
        let song = Song(station: RadioStation(id: "dial:old", name: "Old Dial", streamURL: Self.stream), stream: Self.stream)
        let subject = StationInfoSubject.playing(song, saved: [], tuned: nil, announced: nil)
        #expect(subject?.name == "Old Dial")
        #expect(subject?.savedIn == nil)
        #expect(StationInfoSubject.playing(Song(id: "so-1", title: "A Song"), saved: [], tuned: nil, announced: nil) == nil)
    }
}

@MainActor
struct StationInfoModelTests {
    private actor Asked {
        var listings = 0
        var headers: [URL] = []
        func listing() { listings += 1 }
        func header(_ url: URL) { headers.append(url) }
    }

    private func model(_ asked: Asked) -> StationInfoModel {
        StationInfoModel(sources: .init(
            listing: { _, _ in await asked.listing(); return RadioBrowserStation(id: "u-1", name: "Waves", streamURL: URL(string: "https://x.example.com")!) },
            headers: { url in await asked.header(url); return ["icy-genre": "Rock"] }
        ))
    }

    @Test func onlyHTTPSStreamsAreAskedAndRadioBrowserOnlyWhenOn() async {
        let asked = Asked()
        let info = model(asked)
        let plain = StationInfoSubject(name: "Plain", stream: URL(string: "http://radio.example.org:8000/;")!)
        await info.load(plain, playing: nil, lookUpOnline: false)
        #expect(await asked.headers.isEmpty)
        #expect(await asked.listings == 0)
        #expect(info.listing == nil)

        let secure = StationInfoSubject(name: "Secure", stream: URL(string: "https://example.com/list.pls")!)
        await info.load(secure, playing: URL(string: "https://stream.example.com/live")!, lookUpOnline: true)
        // The headers come from what's actually streamed, not the playlist file.
        #expect(await asked.headers == [URL(string: "https://stream.example.com/live")!])
        #expect(await asked.listings == 1)
        #expect(info.headers?.genre == "Rock")
        #expect(info.listing?.id == "u-1")
    }
}
