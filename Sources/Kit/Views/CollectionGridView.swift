import SwiftData
import SwiftUI

/// The cover wall: a scalable grid of thumbs, sorted on the store rather than in memory.
///
/// The sort lives in the `@Query` descriptor, so changing it re-fetches instead of re-sorting an
/// array, and the grid stays lazy.
struct CollectionGridView: View {
    @Query private var items: [CachedCollectionItem]

    private let itemWidth: CGFloat
    private let onSelect: (CachedCollectionItem) -> Void

    init(
        sort: CollectionSortOption,
        direction: SortDirection,
        itemWidth: CGFloat,
        onSelect: @escaping (CachedCollectionItem) -> Void
    ) {
        var descriptor = FetchDescriptor<CachedCollectionItem>()
        descriptor.sortBy = sort.sortDescriptors(direction)
        _items = Query(descriptor)
        self.itemWidth = itemWidth
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: itemWidth), spacing: spacing)],
                spacing: spacing
            ) {
                ForEach(items) { item in
                    Button { onSelect(item) } label: {
                        CoverCell(item: item, edge: itemWidth, showsCaption: itemWidth >= 110)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(spacing)
        }
    }

    /// Tight covers at high density read as a wall; loose ones at low density read as cards.
    private var spacing: CGFloat {
        itemWidth < 100 ? 6 : 12
    }
}

private struct CoverCell: View {
    let item: CachedCollectionItem
    let edge: CGFloat
    let showsCaption: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImageView(
                releaseID: item.releaseID,
                remoteURL: item.thumbURL,
                kind: .thumb,
                edge: edge
            )
            .frame(width: edge, height: edge)
            .clipShape(.rect(cornerRadius: edge < 100 ? 3 : 6))

            if showsCaption {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.caption)
                        .lineLimit(1)
                    Text(item.artistName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: edge, alignment: .leading)
            }
        }
        .help("\(item.artistName) — \(item.title)")
    }
}
