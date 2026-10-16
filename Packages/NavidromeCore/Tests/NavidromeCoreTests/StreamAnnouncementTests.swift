import Testing
@testable import NavidromeCore

struct StreamAnnouncementTests {
    @Test func aSeparateArtistAndTitleAreJoined() {
        #expect(StreamAnnouncement.combined(title: "Times Like These", artist: "Foo Fighters") == "Foo Fighters - Times Like These")
        #expect(OnAirSong(announced: StreamAnnouncement.combined(title: " Times Like These ", artist: "Foo Fighters\n") ?? "", stationName: nil)
            == OnAirSong(artist: "Foo Fighters", title: "Times Like These"))
    }

    @Test func aTitleThatNamesTheArtistIsLeftAlone() {
        #expect(StreamAnnouncement.combined(title: "Foo Fighters - Times Like These", artist: "foo fighters") == "Foo Fighters - Times Like These")
    }

    @Test func eitherAloneIsKeptAndNeitherIsNothing() {
        #expect(StreamAnnouncement.combined(title: "Rock 102", artist: nil) == "Rock 102")
        #expect(StreamAnnouncement.combined(title: "Rock 102", artist: "  ") == "Rock 102")
        #expect(StreamAnnouncement.combined(title: nil, artist: "Foo Fighters") == "Foo Fighters")
        #expect(StreamAnnouncement.combined(title: " ", artist: nil) == nil)
    }
}
