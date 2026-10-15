import Foundation
import Testing
@testable import NavidromeCore

struct HomeScreenActionTests {
    @Test func continueIsOfferedOnlyWithSomethingToContinue() {
        #expect(HomeScreenAction.available(current: nil) == [.randomMix, .myCuts, .search])
        #expect(HomeScreenAction.available(current: Song(id: "so-1", title: "Dawn")) == [.resume, .randomMix, .myCuts, .search])
    }

    @Test func typesRoundTrip() {
        for action in HomeScreenAction.allCases {
            #expect(HomeScreenAction(type: action.type) == action)
        }
        #expect(HomeScreenAction(type: "com.example.other.search") == nil)
        #expect(HomeScreenAction(type: HomeScreenAction.typePrefix + "nonsense") == nil)
    }

    @Test func continueSaysWhatItContinues() {
        #expect(HomeScreenAction.resumeSubtitle(for: Song(id: "so-1", title: "Dawn", artist: "The Placeholders")) == "Dawn · The Placeholders")
        #expect(HomeScreenAction.resumeSubtitle(for: Song(id: "so-1", title: "Dawn")) == "Dawn")
        let station = RadioStation(id: "rs-1", name: "Night Waves", streamURL: URL(string: "https://stream.example.com/waves")!)
        #expect(HomeScreenAction.resumeSubtitle(for: Song(station: station, stream: station.streamURL)) == "Night Waves")
    }
}
