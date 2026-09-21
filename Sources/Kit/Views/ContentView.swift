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
    @State private var isAdding = false
    @State private var editor: CollectionEditor?
    @State private var pendingRemoval: CachedCollectionItem?

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
                .sheet(isPresented: $isAdding) {
                    AddRecordView()
                        .environment(services)
                        .modelContainer(services.modelContainer)
                }
        }
        .task {
            if syncController == nil { syncController = SyncController(services: services) }
            if editor == nil { editor = services.makeEditor() }
        }
        .confirmationDialog(
            "Remove this copy?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { item in
            Button("Remove from Collection", role: .destructive) {
                Task { await editor?.remove(instanceID: item.instanceID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("\(item.artistName) — \(item.title)\nThis removes the copy from Discogs. Other copies of the same release are unaffected.")
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
                Button("Add a Record") { isAdding = true }
            }
        } else {
            CollectionGridView(
                sort: sort,
                direction: direction,
                itemWidth: itemWidth,
                onSelect: { selection = $0 },
                onRequestRemove: { pendingRemoval = $0 }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if services.hasToken {
            addButton
            sortMenu
            refreshButton
        }
    }

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        ToolbarItem {
            Button {
                isAdding = true
            } label: {
                Label("Add Record", systemImage: "plus")
            }
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
                } else if let errorMessage = editor?.errorMessage ?? syncController?.errorMessage {
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
