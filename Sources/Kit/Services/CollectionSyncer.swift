import DiscogsKit
import Foundation

/// Drives a full refresh: Discogs pages in, the SwiftData cache is reconciled against it, then
/// thumbs are warmed so the grid fills in.
///
/// Reconciliation is by `instanceID`, and anything the server no longer reports is dropped, so a
/// copy removed on discogs.com disappears here on the next refresh.
actor CollectionSyncer {
    struct Progress: Sendable {
        var page: Int
        var totalPages: Int
        var itemsFetched: Int
        var totalItems: Int
    }

    struct Summary: Sendable {
        var username: String
        var itemsSynced: Int
        var itemsRemoved: Int
        var imagesFetched: Int
    }

    private let client: DiscogsClient
    private let store: CollectionStore
    private let imageCache: ImageCache

    init(client: DiscogsClient, store: CollectionStore, imageCache: ImageCache) {
        self.client = client
        self.store = store
        self.imageCache = imageCache
    }

    /// Reconciles the whole collection, then warms the thumb cache.
    ///
    /// - Parameter onProgress: called after each page so the UI can fill in during a first sync.
    @discardableResult
    func sync(onProgress: (@Sendable (Progress) -> Void)? = nil) async throws -> Summary {
        let identity = try await client.identity()

        let folders = try await client.folders(user: identity.username)
        try await store.replaceFolders(folders)

        var seenInstanceIDs = Set<Int>()
        var itemsSynced = 0
        var artworkTargets: [(releaseID: Int, url: URL, kind: ImageCache.Kind)] = []

        for try await page in client.collectionPages(user: identity.username) {
            try Task.checkCancellation()
            try await store.upsert(page.releases)

            for item in page.releases {
                seenInstanceIDs.insert(item.instanceID)
                // The grid draws cover art, so that is what is worth having on disk before the
                // user scrolls. The thumb is only a fallback for releases with no cover.
                let source = item.basicInformation.coverImage ?? item.basicInformation.thumb
                let kind: ImageCache.Kind = item.basicInformation.coverImage == nil ? .thumb : .cover
                if let source, let url = URL(string: source) {
                    artworkTargets.append((item.releaseID, url, kind))
                }
            }
            itemsSynced += page.releases.count

            onProgress?(Progress(
                page: page.pagination.page,
                totalPages: page.pagination.pages,
                itemsFetched: itemsSynced,
                totalItems: page.pagination.items
            ))
        }

        let itemsRemoved = try await store.pruneItems(keeping: seenInstanceIDs)
        let imagesFetched = await warmArtwork(artworkTargets)

        return Summary(
            username: identity.username,
            itemsSynced: itemsSynced,
            itemsRemoved: itemsRemoved,
            imagesFetched: imagesFetched
        )
    }

    /// Downloads any artwork not already on disk. Failures are skipped: a missing cover must not
    /// fail a sync that otherwise succeeded, and the next refresh will try again.
    private func warmArtwork(_ targets: [(releaseID: Int, url: URL, kind: ImageCache.Kind)]) async -> Int {
        await withTaskGroup(of: Bool.self) { group in
            for target in targets {
                group.addTask { [imageCache] in
                    if await imageCache.isCached(releaseID: target.releaseID, kind: target.kind) {
                        return false
                    }
                    do {
                        try await imageCache.localURL(
                            releaseID: target.releaseID,
                            kind: target.kind,
                            remoteURL: target.url
                        )
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var fetched = 0
            for await didFetch in group where didFetch { fetched += 1 }
            return fetched
        }
    }
}
