import DiscogsKit
import Foundation

/// A copy being added, described well enough to render in the grid before Discogs confirms it.
///
/// The optimistic insert is built from the search result, which is all the app knows at that point.
/// Search titles are a combined `Artist - Title`, so the split can be imperfect; the release fetch
/// that follows a successful add corrects it.
struct PendingAddition: Sendable, Hashable {
    var instanceID: Int
    var releaseID: Int
    var folderID: Int
    var dateAdded: Date
    var title: String
    var artistName: String
    var year: Int?
    var thumbURL: String?
    var coverURL: String?
    var formatSummary: String
    var labelName: String?
    var catalogNumber: String?
    var genres: [String]
    var styles: [String]

    init(from result: SearchResult, instanceID: Int, folderID: Int, dateAdded: Date = .now) {
        self.instanceID = instanceID
        self.releaseID = result.id
        self.folderID = folderID
        self.dateAdded = dateAdded
        title = result.releaseTitle
        artistName = result.artistName ?? ""
        year = result.year
        thumbURL = result.thumb
        coverURL = result.coverImage
        formatSummary = result.formatDisplayName
        labelName = result.label.first
        catalogNumber = result.catno
        genres = result.genre
        styles = result.style
    }

    /// Seeded from the clock so ids do not repeat across launches, then stepped monotonically.
    ///
    /// A random suffix is not enough: `instanceID` is a unique attribute, so two provisional ids
    /// that collide would silently overwrite one another instead of producing two rows.
    @MainActor private static var lastProvisionalID = -abs(Int(Date().timeIntervalSince1970 * 1000))

    /// Provisional ids are negative, so they can never collide with a real Discogs `instance_id`.
    @MainActor
    static func provisionalInstanceID() -> Int {
        lastProvisionalID -= 1
        return lastProvisionalID
    }
}
