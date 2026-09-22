import DiscogsKit
import SwiftUI

/// Search Discogs, pick the exact release, confirm, add.
///
/// Search runs on submit rather than per keystroke: the rate limit is 60 requests a minute, and
/// typing an album name would spend most of it.
struct AddRecordView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var confirming: SearchResult?
    @State private var editor: CollectionEditor?
    @State private var hoveredResultID: Int?
    @State private var search: ReleaseSearchController?
    /// Shown when there is no client to search with, which is not a search failure.
    @State private var noTokenMessage: String?

    private var state: ReleaseSearchController.State { search?.state ?? .idle }
    private var results: [SearchResult] { search?.results ?? [] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                if let message = noTokenMessage {
                    banner(message)
                }
                if editor?.isWorking == true {
                    ProgressView("Adding…")
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Add Record")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // A macOS sheet sizes itself to its content, and a List inside a VStack reports no height
        // of its own. Without an explicit size the results area collapses to nothing and the sheet
        // renders as a search field over blank space.
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: 620)
        #endif
        .task {
            editor = editor ?? services.makeEditor()
            if search == nil, let client = services.client {
                search = ReleaseSearchController(client: client)
            }
        }
        .onDisappear { search?.cancel() }
        .collectionFailureAlert(editor)
        .alert(
            "Add this release?",
            isPresented: Binding(
                get: { confirming != nil },
                set: { if !$0 { confirming = nil } }
            ),
            presenting: confirming
        ) { result in
            Button("Add") { Task { await add(result) } }
            Button("Cancel", role: .cancel) {}
        } message: { result in
            Text(confirmationMessage(for: result))
        }
    }

    /// An explicit field and button rather than `.searchable`: the toolbar search field's submit
    /// action does not fire reliably inside a sheet on macOS, which left the view with no way to
    /// start a search and no sign that anything was wrong.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Artist, title, or catalog number", text: $query)
                .textFieldStyle(.plain)
                .onSubmit(startSearch)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Button("Search", action: startSearch)
                .keyboardShortcut(.defaultAction)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
        }
        .padding(12)
    }

    private var isSearching: Bool { state == .searching }

    private func startSearch() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Never fail silently: an unreachable client looks exactly like a search that did nothing.
        guard let search else {
            noTokenMessage = "No Discogs token."
            return
        }
        noTokenMessage = nil
        search.search(query)
    }

    private func banner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            ContentUnavailableView(
                "Find a Record",
                systemImage: "magnifyingglass",
                description: Text("Search Discogs for the release you own.")
            )
        case .searching:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Search Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: startSearch)
            }
        case .loaded(let total) where results.isEmpty:
            ContentUnavailableView.search(text: query)
                .overlay(alignment: .bottom) {
                    if total > 0 { Text("No matches shown").font(.footnote) }
                }
        case .loaded(let total):
            List {
                Section {
                    ForEach(results) { result in
                        Button { confirming = result } label: {
                            SearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                        .disabled(editor?.isWorking ?? false)
                        .rowHoverHighlight(id: result.id, hovered: $hoveredResultID)
                    }
                } footer: {
                    if total > results.count {
                        Text("Showing \(results.count) of \(total) matches.")
                    }
                }
            }
        }
    }

    /// Names the row that was tapped, in the words that row used: one line for the release, one
    /// for the edition. Four separate lines read as a form rather than a sentence.
    private func confirmationMessage(for result: SearchResult) -> String {
        let release = "\(result.artistName ?? "Unknown artist") — \(result.releaseTitle)"
        let details = result.editionDetails
        return details.isEmpty ? release : "\(release)\n\(details)"
    }

    private func add(_ result: SearchResult) async {
        guard let editor else { return }
        if await editor.add(result) {
            dismiss()
        }
    }
}

private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        ReleaseRow(
            releaseID: result.id,
            remoteURL: result.thumb,
            kind: .thumb,
            title: result.releaseTitle,
            artist: result.artistName ?? "Unknown artist",
            details: result.editionDetails
        )
    }
}

private extension SearchResult {
    /// The details that separate one edition from another. Richer than the collection's row:
    /// picking the right one out of a page of near-identical results is exactly what the label and
    /// catalogue number are for.
    ///
    /// Built once, so the confirmation always describes precisely the row that was tapped.
    var editionDetails: String {
        ReleaseRow.details([
            year.map(String.init),
            country,
            label.first,
            catno,
            formatDisplayName,
        ])
    }
}
