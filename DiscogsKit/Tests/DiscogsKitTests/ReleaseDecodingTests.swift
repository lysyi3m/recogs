import Foundation
import Testing
@testable import DiscogsKit

@Suite("Release decoding")
struct ReleaseDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try DiscogsClient.makeDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("A release decodes its tracklist, images and pressing details")
    func release() throws {
        let json = """
        {
          "id": 1373891,
          "title": "Remain In Light",
          "year": 1980,
          "released": "1980-10-08",
          "country": "US",
          "notes": "Gatefold sleeve.",
          "uri": "https://www.discogs.com/release/1373891",
          "artists": [{ "id": 14093, "name": "Talking Heads", "join": "" }],
          "labels": [{ "id": 1000, "name": "Sire", "catno": "SRK 6095" }],
          "formats": [{ "name": "Vinyl", "qty": "1", "descriptions": ["LP", "Album"] }],
          "genres": ["Rock"],
          "styles": ["New Wave"],
          "tracklist": [
            { "position": "", "type_": "heading", "title": "Side A", "duration": "" },
            { "position": "A1", "type_": "track", "title": "Born Under Punches", "duration": "5:46" },
            { "position": "A2", "type_": "track", "title": "Crosseyed And Painless", "duration": "4:45" }
          ],
          "images": [
            { "type": "secondary", "uri": "https://i.discogs.com/back.jpeg", "uri150": "https://i.discogs.com/back-150.jpeg", "width": 600, "height": 600 },
            { "type": "primary", "uri": "https://i.discogs.com/front.jpeg", "uri150": "https://i.discogs.com/front-150.jpeg", "width": 600, "height": 600 }
          ]
        }
        """
        let release = try decode(Release.self, from: json)

        #expect(release.id == 1373891)
        #expect(release.artistDisplayName == "Talking Heads")
        #expect(release.formatDisplayName == "Vinyl, LP, Album")
        #expect(release.released == "1980-10-08")
        #expect(release.country == "US")

        #expect(release.tracklist.count == 3)
        #expect(release.tracklist.filter(\.isTrack).count == 2, "the heading is not a track")
        #expect(release.tracklist[1].position == "A1")
        #expect(release.tracklist[1].duration == "5:46")

        #expect(release.primaryImage?.uri == "https://i.discogs.com/front.jpeg",
                "the primary image wins over document order")
    }

    @Test("A sparse release decodes without a tracklist or images")
    func sparseRelease() throws {
        let json = """
        { "id": 1, "title": "Untitled", "year": 0 }
        """
        let release = try decode(Release.self, from: json)

        #expect(release.year == nil)
        #expect(release.tracklist.isEmpty)
        #expect(release.images.isEmpty)
        #expect(release.primaryImage == nil)
        #expect(release.artistDisplayName.isEmpty)
    }

    @Test("A track missing its type defaults to being a track")
    func trackDefaults() throws {
        let track = try decode(Track.self, from: """
        { "position": "B3", "title": "Listening Wind" }
        """)
        #expect(track.isTrack)
        #expect(track.duration.isEmpty)
    }
}
