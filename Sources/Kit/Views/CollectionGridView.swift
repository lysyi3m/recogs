import SwiftData
import SwiftUI

/// The cover wall: a scalable grid of thumbs, sorted on the store rather than in memory.
///
/// The sort lives in the `@Query` descriptor, so changing it re-fetches instead of re-sorting an
/// array, and the grid stays lazy.
struct CollectionGridView: View {
    @Query private var items: [CachedCollectionItem]

    /// The density the macOS slider drives. iOS sizes its cells from the screen instead.
    private let itemWidth: CGFloat
    private let searchQuery: String
    private let onSelect: (CachedCollectionItem) -> Void
    private let onRequestRemove: (CachedCollectionItem) -> Void

    init(
        sort: CollectionSortOption,
        direction: SortDirection,
        itemWidth: CGFloat,
        searchQuery: String,
        onSelect: @escaping (CachedCollectionItem) -> Void,
        onRequestRemove: @escaping (CachedCollectionItem) -> Void
    ) {
        var descriptor = FetchDescriptor<CachedCollectionItem>()
        descriptor.sortBy = sort.sortDescriptors(direction)
        // Filtering in the fetch rather than over the results keeps the grid lazy.
        descriptor.predicate = CachedCollectionItem.searchPredicate(matching: searchQuery)
        _items = Query(descriptor)
        self.searchQuery = searchQuery
        self.itemWidth = itemWidth
        self.onSelect = onSelect
        self.onRequestRemove = onRequestRemove
    }

    var body: some View {
        if items.isEmpty, !searchQuery.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
        } else {
            #if os(iOS)
            // The covers are the content, so they take the width the device has: two per row on a
            // phone, more on an iPad. The edge is measured rather than assumed because it is also
            // the decode size.
            GeometryReader { proxy in
                let columnCount = max(2, Int(proxy.size.width / 200))
                let edge = max((proxy.size.width - phoneSpacing * CGFloat(columnCount + 1)) / CGFloat(columnCount), 1)
                grid(
                    columns: Array(
                        repeating: GridItem(.fixed(edge), spacing: phoneSpacing),
                        count: columnCount
                    ),
                    spacing: phoneSpacing,
                    edge: edge,
                    showsCaption: true
                )
            }
            #else
            grid(
                columns: [GridItem(.adaptive(minimum: itemWidth), spacing: spacing)],
                spacing: spacing,
                edge: itemWidth,
                showsCaption: itemWidth >= 110
            )
            #endif
        }
    }

    private func grid(
        columns: [GridItem],
        spacing: CGFloat,
        edge: CGFloat,
        showsCaption: Bool
    ) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(items) { item in
                    Button { onSelect(item) } label: {
                        CoverCell(item: item, edge: edge, showsCaption: showsCaption)
                    }
                    .buttonStyle(.plain)
                    // Long press on iOS, right click on macOS.
                    .contextMenu {
                        Button("Open") { onSelect(item) }
                        Divider()
                        Button("Remove from Collection…", systemImage: "trash", role: .destructive) {
                            onRequestRemove(item)
                        }
                    }
                }
            }
            .padding(spacing)
        }
    }

    #if os(iOS)
    private var phoneSpacing: CGFloat { 16 }
    #else
    /// Tight covers at high density read as a wall; loose ones at low density read as cards.
    private var spacing: CGFloat {
        itemWidth < 100 ? 6 : 12
    }
    #endif
}

private struct CoverCell: View {
    let item: CachedCollectionItem
    let edge: CGFloat
    let showsCaption: Bool

    @State private var isHovered = false

    private var cornerRadius: CGFloat { edge < 100 ? 3 : 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CoverImageView(
                releaseID: item.releaseID,
                remoteURL: item.artwork.url,
                kind: item.artwork.kind,
                edge: edge
            )
            .frame(width: edge, height: edge)
            .clipShape(.rect(cornerRadius: cornerRadius))
            // A sleeve with a pale background has no edge of its own and dissolves into the page.
            // The hairline gives every cover the same silhouette, whatever the art does.
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(isHovered ? 0.22 : 0.10), radius: isHovered ? 8 : 3, y: isHovered ? 4 : 1)
            .scaleEffect(isHovered ? 1.025 : 1)

            if showsCaption {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(item.artistName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(width: edge, alignment: .leading)
            }
        }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
        .help("\(item.artistName) — \(item.title)")
    }
}
