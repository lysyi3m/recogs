import DiscogsKit
import SwiftData
import SwiftUI

public struct ContentView: View {
    @Environment(AppServices.self) private var services
    @Query private var allItems: [CachedCollectionItem]

    @AppStorage("collectionSort") private var sortRaw = CollectionSortOption.default.rawValue
    @AppStorage("collectionSortDirection") private var directionRaw = CollectionSortOption.defaultOrder.rawValue
    @AppStorage("collectionItemWidth") private var itemWidth = 120.0

    @State private var syncController: SyncController?
    @State private var selection: CachedCollectionItem?

    public init() {}

    private var sort: CollectionSortOption {
        CollectionSortOption(rawValue: sortRaw) ?? .default
    }

    private var direction: SortDirection {
        SortDirection(rawValue: directionRaw) ?? CollectionSortOption.defaultOrder
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Collection")
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { densityBar }
                .navigationDestination(item: $selection) { item in
                    RecordDetailView(item: item)
                }
        }
        .task {
            if syncController == nil { syncController = SyncController(services: services) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !services.hasToken {
            SetupView()
        } else if allItems.isEmpty {
            ContentUnavailableView {
                Label("No Records Yet", systemImage: "square.stack")
            } description: {
                Text("Sync to pull your Discogs collection onto this device.")
            } actions: {
                Button("Sync Now") { Task { await syncController?.sync() } }
                    .disabled(syncController?.isSyncing ?? true)
            }
        } else {
            CollectionGridView(
                sort: sort,
                direction: direction,
                itemWidth: itemWidth
            ) { selection = $0 }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if services.hasToken {
            sortMenu
            refreshButton
        }
    }

    @ToolbarContentBuilder
    private var sortMenu: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker("Sort By", selection: $sortRaw) {
                    ForEach(CollectionSortOption.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                Divider()
                Picker("Order", selection: $directionRaw) {
                    ForEach(SortDirection.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    @ToolbarContentBuilder
    private var refreshButton: some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await syncController?.sync() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(syncController?.isSyncing ?? true)
        }
    }

    @ViewBuilder
    private var densityBar: some View {
        if services.hasToken, !allItems.isEmpty {
            VStack(spacing: 4) {
                if let progress = syncController?.progress {
                    ProgressView(
                        value: Double(progress.itemsFetched),
                        total: Double(max(progress.totalItems, 1))
                    )
                    .progressViewStyle(.linear)
                } else if let errorMessage = syncController?.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Image(systemName: "square.grid.4x3.fill").imageScale(.small)
                    // Inverted: dragging right means denser, so smaller covers.
                    Slider(value: $itemWidth, in: 60...260)
                    Image(systemName: "square.fill").imageScale(.small)
                    Text("\(allItems.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

#Preview {
    let container = try! AppServices.makeModelContainer(inMemory: true)
    return ContentView()
        .environment(AppServices(modelContainer: container))
        .modelContainer(container)
}
