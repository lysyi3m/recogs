import DiscogsKit
import SwiftData
import SwiftUI

public struct ContentView: View {
    @Environment(AppServices.self) private var services

    private var syncController: SyncController { services.syncController }
    @Query private var allItems: [CachedCollectionItem]

    @AppStorage("collectionSort") private var sortRaw = CollectionSortOption.default.rawValue
    @AppStorage("collectionSortDirection") private var directionRaw = CollectionSortOption.defaultOrder.rawValue
    @AppStorage("collectionItemWidth") private var itemWidth = 120.0

    @State private var selection: CachedCollectionItem?
    @State private var isAdding = false
    @State private var searchQuery = ""
    @State private var editor: CollectionEditor?
    @State private var pendingRemoval: CachedCollectionItem?
    #if os(iOS)
    // iOS has no Settings scene, so it gets a toolbar button and a sheet instead.
    @State private var isShowingSettings = false
    #endif

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
                // Without this the empty and loading states size to their own content, and the
                // bottom bar rides up with them instead of staying at the window edge.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // First run has no collection to title, and "Collection" above "Welcome to
                // Recogs" reads as a stray label.
                .navigationTitle(services.hasToken ? "Collection" : "")
                #if os(iOS)
                .navigationBarTitleDisplayMode(services.hasToken ? .large : .inline)
                #endif
                .toolbar { toolbarContent }
                // Filters the cached collection as you type; the add sheet is what searches
                // Discogs itself.
                .searchable(
                    text: $searchQuery,
                    placement: .toolbar,
                    prompt: "Find in Collection"
                )
                .navigationDestination(item: $selection) { item in
                    RecordDetailView(item: item)
                }
                .sheet(isPresented: $isAdding) {
                    AddRecordView()
                        .environment(services)
                        .modelContainer(services.modelContainer)
                }
                #if os(iOS)
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView { isShowingSettings = false }
                        .environment(services)
                        .modelContainer(services.modelContainer)
                }
                #endif
        }
        #if os(macOS)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
        // Outside the stack, so the status stays visible on the record detail too.
        .safeAreaInset(edge: .bottom) { statusBar }
        .task {
            if editor == nil { editor = services.makeEditor() }
            // On-launch delta, skipped when a sync ran moments ago.
            if syncController.shouldSyncOnLaunch { await syncController.sync() }
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
            SetupView { Task { await syncController.sync() } }
        } else if allItems.isEmpty, syncController.isSyncing {
            // First sync on a fresh install: an empty grid with a spinner beats an empty-state
            // screen that is about to be wrong.
            VStack(spacing: 12) {
                ProgressView()
                Text(initialSyncStatus).font(.callout).foregroundStyle(.secondary)
            }
        } else if allItems.isEmpty {
            ContentUnavailableView {
                Label("No Records Yet", systemImage: "square.stack")
            } description: {
                Text("Sync to pull your Discogs collection onto this device.")
            } actions: {
                Button("Sync Now") { Task { await syncController.sync() } }
                    .disabled(syncController.isSyncing)
                Button("Add a Record") { isAdding = true }
            }
        } else {
            CollectionGridView(
                sort: sort,
                direction: direction,
                itemWidth: itemWidth,
                searchQuery: searchQuery,
                onSelect: { selection = $0 },
                onRequestRemove: { pendingRemoval = $0 }
            )
            .refreshable { await syncController.sync() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if services.hasToken {
            addButton
            sortMenu
            refreshButton
            #if os(iOS)
            settingsButton
            #endif
        }
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var settingsButton: some ToolbarContent {
        ToolbarItem {
            Button {
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
    #endif

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
                // Inline, so the keys and the direction sit in one flat menu with checkmarks.
                // A plain picker in a menu becomes a submenu, which buries a two-click choice.
                Picker("Sort By", selection: $sortRaw) {
                    ForEach(CollectionSortOption.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Picker("Order", selection: $directionRaw) {
                    ForEach(SortDirection.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    @ToolbarContentBuilder
    private var refreshButton: some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await syncController.sync() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(syncController.isSyncing)
        }
    }

    private var initialSyncStatus: String {
        guard let progress = syncController.progress else { return "Fetching your collection…" }
        return "\(progress.itemsFetched) of \(progress.totalItems) records"
    }

    /// One row: what you can change on the left, what is happening on the right.
    @ViewBuilder
    private var statusBar: some View {
        if services.hasToken {
            VStack(spacing: 0) {
                // Without this the bar is invisible against the record detail's light background.
                Divider()
                barContents
            }
            .background(.bar)
        }
    }

    private var barContents: some View {
        HStack(spacing: 12) {
            // The density control belongs to the grid, so it goes away on the detail screen.
            if selection == nil { densityControls }
            Spacer(minLength: 12)
            syncStatus
        }
        // Overlaid rather than placed between the two, so it centres on the bar itself and does
        // not drift as the status text changes length.
        .overlay {
            if selection == nil {
                countLabel
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
    }

    /// Reads as a plain count normally, and says how much of the collection is showing while a
    /// search narrows it. Built as `Text` so the inflection markup is actually resolved.
    @ViewBuilder
    private var countLabel: some View {
        if searchQuery.isEmpty {
            Text("^[\(allItems.count) record](inflect: true)")
        } else {
            Text("\(matchCount) of \(allItems.count)")
        }
    }

    private var matchCount: Int {
        let predicate = CachedCollectionItem.searchPredicate(matching: searchQuery)
        return allItems.filter { (try? predicate.evaluate($0)) ?? false }.count
    }

    private var densityControls: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.3x3.fill").imageScale(.small)
            Slider(value: $itemWidth, in: 60...260)
                .frame(width: 140)
                .controlSize(.small)
            Image(systemName: "square.fill").imageScale(.small)
        }
        .foregroundStyle(.secondary)
    }

    /// Always says something: a sync in flight, a problem, or when it last worked.
    @ViewBuilder
    private var syncStatus: some View {
        if let progress = syncController.progress {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Syncing \(progress.itemsFetched) of \(progress.totalItems)")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        } else if syncController.isSyncing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Syncing…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let errorMessage = editor?.errorMessage ?? syncController.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(errorMessage)
        } else if syncController.isOffline {
            Label("Offline — showing cached collection", systemImage: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let lastSyncedAt = syncController.lastSyncedAt {
            Text("Synced \(lastSyncedAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("Not synced yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let container = try! AppServices.makeModelContainer(inMemory: true)
    return ContentView()
        .environment(AppServices(modelContainer: container))
        .modelContainer(container)
}
