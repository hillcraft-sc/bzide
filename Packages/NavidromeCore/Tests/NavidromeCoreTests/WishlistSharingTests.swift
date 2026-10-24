import Foundation
import Testing
@testable import NavidromeCore

/// Buying from the Wishlist and sharing it (Gitea #29).
@MainActor
struct WishlistSharingTests {
    private let defaults = UserDefaults(suiteName: "WishlistSharingTests-\(UUID().uuidString)")!
    private let file = URL.temporaryDirectory.appending(path: "WishlistSharingTests-\(UUID().uuidString)/Wishlist.json")

    private func wishlist() -> Wishlist {
        Wishlist(fileURL: file, defaults: defaults, search: { _ async throws(SubsonicError) in [] }, now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    @Test func storesSearchForTheSong() {
        let entry = WishlistEntry(artist: "Looking Glass", title: "Brandy", heardAt: .now)
        let links = entry.storeLinks(region: "US")
        #expect(links.map(\.store) == ["Apple Music", "Bandcamp", "Qobuz", "Amazon"])
        #expect(links[0].url.absoluteString == "https://music.apple.com/search?term=Looking%20Glass%20Brandy")
        #expect(links[1].url.absoluteString == "https://bandcamp.com/search?q=Looking%20Glass%20Brandy&item_type=t")
        #expect(links[2].url.absoluteString == "https://www.qobuz.com/us-en/search?q=Looking%20Glass%20Brandy")
        #expect(links[3].url.absoluteString == "https://www.amazon.com/s?k=Looking%20Glass%20Brandy&i=digital-music")
    }

    @Test func albumsAndArtistsAreSearchedAsSuch() {
        let album = WishlistEntry(kind: .album, artist: "Creed", title: "Weathered", heardAt: .now)
        #expect(album.storeLinks(region: "US")[1].url.query()?.contains("item_type=a") == true)
        let artist = WishlistEntry(kind: .artist, artist: "Glass Harbor", title: "Glass Harbor", heardAt: .now)
        #expect(artist.storeLinks(region: "US")[0].url.absoluteString == "https://music.apple.com/search?term=Glass%20Harbor")
        #expect(artist.storeLinks(region: "US")[1].url.query()?.contains("item_type=b") == true)
    }

    @Test func storesFollowTheRegionElseTheUSStore() {
        let entry = WishlistEntry(artist: "Blur", title: "Song 2", heardAt: .now)
        let british = entry.storeLinks(region: "GB")
        #expect(british[2].url.absoluteString.hasPrefix("https://www.qobuz.com/gb-en/"))
        #expect(british[3].url.host() == "www.amazon.co.uk")
        let elsewhere = entry.storeLinks(region: "BR")
        #expect(elsewhere[2].url.absoluteString.hasPrefix("https://www.qobuz.com/us-en/"))
        #expect(elsewhere[3].url.host() == "www.amazon.com")
    }

    @Test func textExportIsBySection() {
        let list = wishlist()
        list.add(OnAirSong(artist: "Blur", title: "Song 2"), station: "Alt FM", details: nil)
        list.addAlbum(titled: "Weathered", by: "Creed", year: 2001, coverURL: nil, musicBrainzURL: nil)
        list.addArtist(named: "Glass Harbor", musicBrainzURL: nil)
        #expect(list.exportText() == """
            Found on Radio
            - Blur - Song 2 (heard on Alt FM)

            Albums
            - Creed - Weathered (2001)

            Artists
            - Glass Harbor
            """)
    }

    @Test func csvExportQuotesWhatNeedsIt() {
        let list = wishlist()
        list.addMissingSongs(["Brandy, You're a \"Fine\" Girl"], album: "Looking Glass", artist: "Looking Glass", year: 1972, coverURL: nil, musicBrainzURL: URL(string: "https://musicbrainz.org/release/r1"))
        let lines = list.exportCSV().split(separator: "\n")
        #expect(lines.first == "Kind,Artist,Title,Album,Year,Station,Added,MusicBrainz")
        #expect(lines.last == #"Missing Songs,Looking Glass,"Brandy, You're a ""Fine"" Girl",Looking Glass,1972,,2027-01-15,https://musicbrainz.org/release/r1"#)
    }
}
