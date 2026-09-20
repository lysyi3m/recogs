import Foundation
import SwiftData

/// Sort dimensions offered by the collection grid. The default is date added, descending.
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
            // Items with no year sort together; the artist key keeps that group stable.
            return [SortDescriptor(\.year, order: order), SortDescriptor(\.sortArtist)]
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
