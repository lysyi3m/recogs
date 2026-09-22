import SwiftUI

/// One record: cover, the facts that identify the pressing, and its tracklist on request.
///
/// The collection snapshot already holds everything that identifies a pressing, so the page is
/// complete the moment it opens. Only the tracklist needs Discogs, and only when it is opened.
struct RecordDetailView: View {
    let item: CachedCollectionItem

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var loader: ReleaseDetailLoader?
    @State private var editor: CollectionEditor?
    @State private var isConfirmingRemoval = false
    @State private var isTracklistExpanded = false

    private var detail: ReleaseDetailSnapshot? { loader?.snapshot }

    private var pagePadding: CGFloat {
        #if os(macOS)
        28
        #else
        20
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                facts
                tracklist
                notes
            }
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(pagePadding)
        }
        .navigationTitle(item.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { actions }
        .task {
            editor = editor ?? services.makeEditor()
            let loader = loader ?? ReleaseDetailLoader(services: services)
            self.loader = loader
            // Tracklist, notes and country arrive together; one fetch covers the page.
            await loader.load(releaseID: item.releaseID)
        }
        // An alert rather than a confirmation dialog: raised from the toolbar menu, a dialog is
        // presented as a popover anchored to that menu and inherits its width, which crams the
        // message into a few words per line and hides the cancel button behind a tap outside.
        .alert(
            "Remove this copy?",
            isPresented: $isConfirmingRemoval
        ) {
            Button("Remove from Collection", role: .destructive) {
                Task {
                    if await editor?.remove(instanceID: item.instanceID) == true { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(item.artistName) — \(item.title)\nThis removes the copy from Discogs.")
        }
        .collectionFailureAlert(editor)
    }

    // MARK: - Actions

    /// Record-scoped actions live in the toolbar rather than the page body: they are about the
    /// record rather than part of it, and this is where the folder actions will go too.
    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        ToolbarItem {
            Menu {
                if let link = discogsURL {
                    Link(destination: link) {
                        Label("View on Discogs", systemImage: "arrow.up.right.square")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    Label("Remove from Collection", systemImage: "trash")
                }
                .disabled(editor?.isWorking ?? true)
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }
    }

    private var discogsURL: URL? {
        detail?.discogsURL.flatMap(URL.init(string:))
            ?? URL(string: "https://www.discogs.com/release/\(item.releaseID)")
    }

    // MARK: - Header

    /// Which image to show, and which cache slot it belongs in.
    ///
    /// When neither a release nor a collection cover exists the thumb is shown, but as a thumb —
    /// writing it into the cover slot would cache a 150px image as this release's cover
    /// permanently, and nothing would ever replace it.
    private var coverSource: (url: String?, kind: ImageCache.Kind) {
        if let cover = detail?.coverURL, !cover.isEmpty { return (cover, .cover) }
        return item.artwork
    }

    @ViewBuilder
    private var header: some View {
        #if os(iOS)
        // Side by side, a phone leaves the text about 120pt — too narrow for a format summary, and
        // narrow enough that the genre chips collapse to one letter per line. The cover leads
        // instead, the way a record page reads anyway.
        VStack(alignment: .leading, spacing: 18) {
            cover(edge: 240)
                .frame(maxWidth: .infinity, alignment: .center)
            titleBlock
        }
        #else
        HStack(alignment: .top, spacing: 24) {
            cover(edge: 200)
            titleBlock
            Spacer(minLength: 0)
        }
        #endif
    }

    private func cover(edge: CGFloat) -> some View {
        CoverImageView(
            releaseID: item.releaseID,
            remoteURL: coverSource.url,
            kind: coverSource.kind,
            edge: edge
        )
        .frame(width: edge, height: edge)
        .clipShape(.rect(cornerRadius: 8))
        .shadow(radius: 6, y: 3)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            Text(item.artistName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            if !item.genres.isEmpty || !item.styles.isEmpty {
                TagRow(tags: item.genres + item.styles)
                    .padding(.top, 4)
            }
        }
    }

    /// Year and format, the two things that distinguish one pressing from another at a glance.
    private var subtitle: String {
        [item.year.map(String.init), item.formatSummary.isEmpty ? nil : item.formatSummary]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - Facts

    /// The pressing details, as a wrapping grid rather than a column of full-width rows: seven
    /// two-word facts do not need seven lines of a wide window.
    @ViewBuilder
    private var facts: some View {
        let entries = factEntries
        if !entries.isEmpty {
            section("Pressing") {
                LazyVGrid(
                    // Sized so the five usual facts sit on one line at this page's width; a
                    // lone "Added" wrapping to a second row looks like a mistake.
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 16, alignment: .leading)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(entries, id: \.label) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.value)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var factEntries: [(label: String, value: String)] {
        var entries: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            entries.append((label, value))
        }
        add("Label", item.labelName)
        add("Catalog number", item.catalogNumber)
        add("Released", detail?.releasedDisplay)
        add("Country", detail?.country)
        add("Added", item.dateAdded?.formatted(date: .abbreviated, time: .omitted))
        return entries
    }

    // MARK: - Tracklist

    @ViewBuilder
    private var tracklist: some View {
        DisclosureGroup(isExpanded: $isTracklistExpanded) {
            tracklistContent
                .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Text("Tracklist").font(.headline)
                if let count = detail?.playableTracks.count {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if loader?.state == .loading {
                    ProgressView().controlSize(.small)
                }
            }
        }
        #if os(iOS)
        // Left to the accent colour, the section heading reads as a link rather than a heading.
        .tint(.primary)
        #endif
    }

    @ViewBuilder
    private var notes: some View {
        if let notes = detail?.notes, !notes.isEmpty {
            section("Notes") {
                Text(notes)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var tracklistContent: some View {
        switch loader?.state {
        case .loaded(let snapshot) where !snapshot.tracks.isEmpty:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.tracks) { track in
                    TrackRow(track: track)
                    if track.id != snapshot.tracks.last?.id { Divider() }
                }
            }
        case .loaded:
            Text("No tracklist on Discogs.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.callout).foregroundStyle(.red)
                Button("Try Again") {
                    Task { await loader?.load(releaseID: item.releaseID) }
                }
            }
        case .loading, nil:
            Text("Loading…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// Genres and styles as unobtrusive chips, which read faster than a comma-separated list.
private struct TagRow: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags.prefix(5), id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: .capsule)
            }
        }
    }
}

/// Chips that wrap onto the next line rather than being squeezed, which is what an `HStack` does
/// to them when the column is narrower than their combined width.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                height += rowHeight + spacing
                rowHeight = 0
                x = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                rowHeight = 0
                x = bounds.minX
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct TrackRow: View {
    let track: CachedTrack

    var body: some View {
        if track.isTrack {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(track.position)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                Text(track.title).font(.callout)
                Spacer(minLength: 8)
                if !track.duration.isEmpty {
                    Text(track.duration)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        } else {
            Text(track.title)
                .font(.subheadline.weight(.semibold))
                .padding(.top, 12)
                .padding(.bottom, 4)
        }
    }
}
