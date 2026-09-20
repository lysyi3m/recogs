import DiscogsKit
import SwiftData
import SwiftUI

/// Scaffolding for step 2 of the build order: it exercises the cache and the sync engine so both
/// can be verified against the real API. The collection grid replaces it in step 3, and the token
/// field gives way to the first-run screen in step 7.
public struct ContentView: View {
    @Environment(AppServices.self) private var services
    @Query private var items: [CachedCollectionItem]

    @State private var token = ""
    @State private var status = ""
    @State private var progress: CollectionSyncer.Progress?
    @State private var isBusy = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        Form {
            Section("Cache") {
                LabeledContent("Cached copies", value: "\(items.count)")
                if let newest = items.compactMap(\.dateAdded).max() {
                    LabeledContent("Newest addition", value: newest.formatted(date: .abbreviated, time: .omitted))
                }
            }

            if services.hasToken {
                Section("Sync") {
                    Button("Sync Now", action: sync)
                        .disabled(isBusy)
                    if let progress {
                        ProgressView(
                            value: Double(progress.itemsFetched),
                            total: Double(max(progress.totalItems, 1))
                        ) {
                            Text("Page \(progress.page) of \(progress.totalPages)")
                        }
                    }
                    if !status.isEmpty {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Personal Access Token") {
                    SecureField("Paste your Discogs token", text: $token)
                    Button("Validate and Save", action: signIn)
                        .disabled(token.isEmpty || isBusy)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Recogs")
    }

    private func signIn() {
        run {
            let identity = try await services.signIn(token: token)
            token = ""
            status = "Signed in as \(identity.username)."
        }
    }

    private func sync() {
        guard let syncer = services.makeSyncer() else { return }
        run {
            let summary = try await syncer.sync { update in
                Task { @MainActor in progress = update }
            }
            progress = nil
            status = """
            \(summary.itemsSynced) copies synced, \(summary.itemsRemoved) removed, \
            \(summary.thumbsFetched) thumbs cached.
            """
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }
}

#Preview {
    let container = try! AppServices.makeModelContainer(inMemory: true)
    return ContentView()
        .environment(AppServices(modelContainer: container))
        .modelContainer(container)
}
