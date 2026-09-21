import DiscogsKit
import Foundation

/// Applies collection writes optimistically: the cache changes first, Discogs second, and a failure
/// rolls the cache back.
///
/// The grid therefore reacts the moment the user confirms, and never shows a change Discogs
/// rejected.
@MainActor
@Observable
final class CollectionEditor {
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    /// Adds a copy to the folder, optimistically.
    ///
    /// The row appears immediately from search data under a provisional id, then takes the real
    /// `instance_id` from the response. A release fetch afterwards replaces the search-derived
    /// artist and title with Discogs' own; that refinement is best-effort, because the add itself
    /// has already succeeded by then.
    @discardableResult
    func add(
        _ result: SearchResult,
        folderID: Int = DiscogsFolder.uncategorized
    ) async -> Bool {
        guard !isWorking, let client = services.client else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let provisionalID = PendingAddition.provisionalInstanceID()
        let pending = PendingAddition(from: result, instanceID: provisionalID, folderID: folderID)

        do {
            try await services.store.insert(pending)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        do {
            let username = try await services.username()
            let addition = try await client.addToCollection(
                user: username,
                folderID: folderID,
                releaseID: result.id
            )
            try await services.store.reassignInstanceID(from: provisionalID, to: addition.instanceID)
            await refine(releaseID: result.id, instanceID: addition.instanceID, client: client)
            return true
        } catch {
            errorMessage = error.localizedDescription
            try? await services.store.deleteItem(instanceID: provisionalID)
            return false
        }
    }

    /// Removes a copy from the collection, optimistically.
    ///
    /// Keyed by `instanceID`: removing one of two pressings of the same album must not touch the
    /// other. The row disappears from the grid immediately and comes back if Discogs rejects the
    /// delete.
    @discardableResult
    func remove(instanceID: Int) async -> Bool {
        guard !isWorking, let client = services.client else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let snapshot: CollectionItemSnapshot?
        do {
            snapshot = try await services.store.item(instanceID: instanceID)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        guard let snapshot else { return false }

        do {
            try await services.store.deleteItem(instanceID: instanceID)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        do {
            let username = try await services.username()
            try await client.removeFromCollection(
                user: username,
                folderID: snapshot.folderID,
                releaseID: snapshot.releaseID,
                instanceID: snapshot.instanceID
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            try? await services.store.restore(snapshot)
            return false
        }
    }

    /// Best-effort accuracy pass. A failure here leaves the copy added with search-derived text,
    /// which the next full sync corrects anyway.
    private func refine(releaseID: Int, instanceID: Int, client: DiscogsClient) async {
        do {
            let release = try await client.release(id: releaseID)
            try await services.store.apply(release, toInstanceID: instanceID)
            try await services.store.upsertReleaseDetail(release)
        } catch {
            // Intentionally silent: the add succeeded, and this only sharpens the cached text.
        }
    }
}
