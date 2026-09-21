import SwiftUI

/// Full record view: cover, pressing details, tracklist, and a link out to Discogs.
///
/// Everything already in the collection snapshot renders immediately; only the tracklist and the
/// full-size cover wait on the release fetch, so the screen is never blank.
struct RecordDetailView: View {
    let item: CachedCollectionItem

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var loader: ReleaseDetailLoader?
    @State private var editor: CollectionEditor?
    @State private var isConfirmingRemoval = false

    private var detail: ReleaseDetailSnapshot? {
        if case .loaded(let snapshot) = loader?.state { return snapshot }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metadata
                tracklist
                if let notes = detail?.notes, !notes.isEmpty {
                    section("Notes") {
                        Text(notes).font(.callout)
                    }
                }
                if let link = discogsURL {
                    Link(destination: link) {
                        Label("View on Discogs", systemImage: "arrow.up.right.square")
                    }
                }

                removeSection
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .navigationTitle(item.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            editor = editor ?? services.makeEditor()
            let loader = loader ?? ReleaseDetailLoader(services: services)
            self.loader = loader
            await loader.load(releaseID: item.releaseID)
        }
        .confirmationDialog(
            "Remove this copy?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove from Collection", role: .destructive) {
                Task {
                    if await editor?.remove(instanceID: item.instanceID) == true { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(item.artistName) — \(item.title)\nThis removes the copy from Discogs. Other copies of the same release are unaffected.")
        }
    }

    @ViewBuilder
    private var removeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let message = editor?.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Button(role: .destructive) {
                isConfirmingRemoval = true
            } label: {
                Label("Remove from Collection", systemImage: "trash")
            }
            .disabled(editor?.isWorking ?? true)
            Text("Sold it, or added it by mistake.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Which image to show, and which cache slot it belongs in.
    ///
    /// The full-size image only arrives with the release fetch; the collection snapshot carries a
    /// mid-size cover that stands in until then. When neither exists the thumb is shown, but as a
    /// thumb — writing it into the cover slot would cache a 150px image as this release's cover
    /// permanently, and nothing would ever replace it.
    private var coverSource: (url: String?, kind: ImageCache.Kind) {
        if let cover = detail?.coverURL ?? item.coverURL, !cover.isEmpty {
            return (cover, .cover)
        }
        return (item.thumbURL, .thumb)
    }

    private var discogsURL: URL? {
        detail?.discogsURL.flatMap(URL.init(string:))
            ?? URL(string: "https://www.discogs.com/release/\(item.releaseID)")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            CoverImageView(
                releaseID: item.releaseID,
                remoteURL: coverSource.url,
                kind: coverSource.kind,
                edge: 240
            )
            .frame(width: 240, height: 240)
            .clipShape(.rect(cornerRadius: 8))
            .shadow(radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.title2.weight(.semibold))
                Text(item.artistName).font(.title3).foregroundStyle(.secondary)
                if let year = item.year {
                    Text(String(year)).font(.callout).foregroundStyle(.secondary)
                }
                Text(item.formatSummary).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var metadata: some View {
        section("Pressing") {
            VStack(alignment: .leading, spacing: 6) {
                row("Label", item.labelName)
                row("Catalog number", item.catalogNumber)
                row("Released", detail?.releasedDisplay)
                row("Country", detail?.country)
                row("Genres", item.genres.isEmpty ? nil : item.genres.joined(separator: ", "))
                row("Styles", item.styles.isEmpty ? nil : item.styles.joined(separator: ", "))
                row("Added", item.dateAdded?.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    @ViewBuilder
    private var tracklist: some View {
        section("Tracklist") {
            switch loader?.state {
            case .loaded(let snapshot) where !snapshot.tracks.isEmpty:
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(snapshot.tracks) { track in
                        TrackRow(track: track)
                        if track.id != snapshot.tracks.last?.id { Divider() }
                    }
                }
            case .loaded:
                Text("Discogs lists no tracks for this release.")
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
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                Text(value).font(.callout)
                Spacer(minLength: 0)
            }
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
