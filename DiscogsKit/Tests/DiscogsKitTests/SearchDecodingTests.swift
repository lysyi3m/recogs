import Foundation
import Testing
@testable import DiscogsKit

@Suite("Search decoding")
struct SearchDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try DiscogsClient.makeDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("A search page decodes results and splits the combined title")
    func searchPage() throws {
        let json = """
        {
          "pagination": { "page": 1, "pages": 12, "per_page": 50, "items": 573 },
          "results": [
            {
              "id": 1373891,
              "type": "release",
              "title": "Talking Heads - Remain In Light",
              "year": "1980",
              "country": "US",
              "thumb": "https://i.discogs.com/thumb.jpeg",
              "cover_image": "https://i.discogs.com/cover.jpeg",
              "format": ["Vinyl", "LP", "Album"],
              "label": ["Sire"],
              "catno": "SRK 6095",
              "genre": ["Rock"],
              "style": ["New Wave"],
              "master_id": 34095,
              "resource_url": "https://api.discogs.com/releases/1373891"
            }
          ]
        }
        """
        let page = try decode(SearchPage.self, from: json)

        #expect(page.pagination.items == 573)
        let result = try #require(page.results.first)
        #expect(result.artistName == "Talking Heads")
        #expect(result.releaseTitle == "Remain In Light")
        #expect(result.year == 1980, "search sends the year as a string")
        #expect(result.formatDisplayName == "Vinyl, LP, Album")
        #expect(result.catno == "SRK 6095")
    }

    @Test("A title without the usual separator stays whole")
    func titleWithoutSeparator() throws {
        let result = try decode(SearchResult.self, from: """
        { "id": 1, "title": "Untitled" }
        """)
        #expect(result.artistName == nil)
        #expect(result.releaseTitle == "Untitled")
    }

    @Test("Only the first separator splits, so hyphenated album names survive")
    func hyphenatedTitle() throws {
        let result = try decode(SearchResult.self, from: """
        { "id": 1, "title": "Godspeed You! Black Emperor - F♯A♯∞ - Reissue" }
        """)
        #expect(result.artistName == "Godspeed You! Black Emperor")
        #expect(result.releaseTitle == "F♯A♯∞ - Reissue")
    }

    @Test("Missing, empty and date-shaped years all decode sensibly")
    func yearVariants() throws {
        #expect(try decode(SearchResult.self, from: #"{ "id": 1, "title": "A" }"#).year == nil)
        #expect(try decode(SearchResult.self, from: #"{ "id": 1, "title": "A", "year": "" }"#).year == nil)
        #expect(try decode(SearchResult.self, from: #"{ "id": 1, "title": "A", "year": "0" }"#).year == nil)
        #expect(try decode(SearchResult.self, from: #"{ "id": 1, "title": "A", "year": "1977-05-01" }"#).year == 1977)
    }

    @Test("An add response carries the new instance id")
    func addition() throws {
        let addition = try decode(CollectionAddition.self, from: """
        { "instance_id": 447829291, "resource_url": "https://api.discogs.com/users/x/collection/..." }
        """)
        #expect(addition.instanceID == 447829291)
    }
}
