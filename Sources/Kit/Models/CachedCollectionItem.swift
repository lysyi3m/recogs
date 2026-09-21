import DiscogsKit
import Foundation
import SwiftData

/// One owned copy, mirrored from Discogs.
///
/// This is a cache, never the source of truth: a refresh upserts by `instanceID` and drops rows
/// Discogs no longer reports. The `basic_information` snapshot is flattened into stored properties
/// so the grid can sort and render without a per-record call.
@Model
final class CachedCollectionItem {
    /// Identifies the copy. Two pressings of the same album share a `releaseID` but not this.
    @Attribute(.unique) var instanceID: Int
    var releaseID: Int
    var folderID: Int
    var dateAdded: Date?
    var rating: Int

    var title: String
    /// Pre-joined artist credit, as Discogs would render it.
    var artistName: String
    var year: Int?
    var thumbURL: String?
    var coverURL: String?
    var formatSummary: String
    var labelName: String?
    var catalogNumber: String?
    var genres: [String]
    var styles: [String]

    /// Case-folded sort keys, stored so SwiftData can sort in the store rather than in memory.
    var sortArtist: String
    var sortTitle: String

    init(from item: CollectionItem) {
        instanceID = item.instanceID
        releaseID = item.releaseID
        folderID = item.folderID
        dateAdded = item.dateAdded
        rating = item.rating
        title = item.basicInformation.title
        artistName = item.basicInformation.artistDisplayName
        year = item.basicInformation.year
        thumbURL = item.basicInformation.thumb
        coverURL = item.basicInformation.coverImage
        formatSummary = item.basicInformation.formatDisplayName
        labelName = item.basicInformation.labels.first?.name
        catalogNumber = item.basicInformation.labels.first?.catno
        genres = item.basicInformation.genres
        styles = item.basicInformation.styles
        sortArtist = Self.sortKey(item.basicInformation.artistDisplayName)
        sortTitle = Self.sortKey(item.basicInformation.title)
    }

    /// Builds a row from an optimistic add, before Discogs has confirmed it.
    init(from pending: PendingAddition) {
        instanceID = pending.instanceID
        releaseID = pending.releaseID
        folderID = pending.folderID
        dateAdded = pending.dateAdded
        rating = 0
        title = pending.title
        artistName = pending.artistName
        year = pending.year
        thumbURL = pending.thumbURL
        coverURL = pending.coverURL
        formatSummary = pending.formatSummary
        labelName = pending.labelName
        catalogNumber = pending.catalogNumber
        genres = pending.genres
        styles = pending.styles
        sortArtist = Self.sortKey(pending.artistName)
        sortTitle = Self.sortKey(pending.title)
    }

    /// Rebuilds a row from a snapshot, so a failed removal can be rolled back exactly.
    init(from snapshot: CollectionItemSnapshot) {
        instanceID = snapshot.instanceID
        releaseID = snapshot.releaseID
        folderID = snapshot.folderID
        dateAdded = snapshot.dateAdded
        rating = snapshot.rating
        title = snapshot.title
        artistName = snapshot.artistName
        year = snapshot.year
        thumbURL = snapshot.thumbURL
        coverURL = snapshot.coverURL
        formatSummary = snapshot.formatSummary
        labelName = snapshot.labelName
        catalogNumber = snapshot.catalogNumber
        genres = snapshot.genres
        styles = snapshot.styles
        sortArtist = Self.sortKey(snapshot.artistName)
        sortTitle = Self.sortKey(snapshot.title)
    }

    /// Replaces the search-derived fields with the release's authoritative ones, after an add.
    func apply(_ release: Release) {
        title = release.title
        artistName = release.artistDisplayName
        year = release.year
        formatSummary = release.formatDisplayName
        labelName = release.labels.first?.name
        catalogNumber = release.labels.first?.catno
        genres = release.genres
        styles = release.styles
        if let cover = release.primaryImage?.uri { coverURL = cover }
        sortArtist = Self.sortKey(artistName)
        sortTitle = Self.sortKey(title)
    }

    /// Applies a fresh snapshot in place. Discogs wins on every field.
    func update(from item: CollectionItem) {
        releaseID = item.releaseID
        folderID = item.folderID
        dateAdded = item.dateAdded
        rating = item.rating
        title = item.basicInformation.title
        artistName = item.basicInformation.artistDisplayName
        year = item.basicInformation.year
        thumbURL = item.basicInformation.thumb
        coverURL = item.basicInformation.coverImage
        formatSummary = item.basicInformation.formatDisplayName
        labelName = item.basicInformation.labels.first?.name
        catalogNumber = item.basicInformation.labels.first?.catno
        genres = item.basicInformation.genres
        styles = item.basicInformation.styles
        sortArtist = Self.sortKey(item.basicInformation.artistDisplayName)
        sortTitle = Self.sortKey(item.basicInformation.title)
    }

    /// Lowercases and drops a leading article so "The Beatles" sorts under B.
    static func sortKey(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["the ", "a ", "an "] where folded.hasPrefix(article) {
            return String(folded.dropFirst(article.count))
        }
        return folded
    }
}
