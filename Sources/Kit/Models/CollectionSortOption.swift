import Foundation
import SwiftData

/// How the collection is drawn. A wall of covers is for browsing; rows are for finding a record in
/// a large collection, where the sort key is legible rather than implied by position.
enum CollectionLayout: String, CaseIterable, Identifiable, Sendable {
    case grid
    case list

    static let `default` = CollectionLayout.grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: return "Grid"
        case .list: return "List"
        }
    }

    var symbol: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

/// Sort dimensions offered by the collection. The default is date added, descending.
enum CollectionSortOption: String, CaseIterable, Identifiable, Sendable {
    case dateAdded
    case artist
    case title
    case year

    static let `default` = CollectionSortOption.dateAdded
    static let defaultOrder = SortDirection.descending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .artist: return "Artist"
        case .title: return "Title"
        case .year: return "Year"
        }
    }

    func sortDescriptors(_ direction: SortDirection) -> [SortDescriptor<CachedCollectionItem>] {
        let order = direction.sortOrder
        switch self {
        case .dateAdded:
            return [SortDescriptor(\.dateAdded, order: order), SortDescriptor(\.sortArtist)]
        case .artist:
            return [SortDescriptor(\.sortArtist, order: order), SortDescriptor(\.sortTitle)]
        case .title:
            return [SortDescriptor(\.sortTitle, order: order), SortDescriptor(\.sortArtist)]
        case .year:
            // Rank first, so records Discogs has no year for land after every dated one in both
            // directions. The artist key keeps that group stable.
            return [
                SortDescriptor(\.yearRank),
                SortDescriptor(\.year, order: order),
                SortDescriptor(\.sortArtist),
            ]
        }
    }
}

enum SortDirection: String, CaseIterable, Identifiable, Sendable {
    case ascending
    case descending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ascending: return "Ascending"
        case .descending: return "Descending"
        }
    }

    var sortOrder: SortOrder {
        switch self {
        case .ascending: return .forward
        case .descending: return .reverse
        }
    }

    var toggled: SortDirection {
        self == .ascending ? .descending : .ascending
    }
}
