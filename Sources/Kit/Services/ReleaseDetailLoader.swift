import DiscogsKit
import Foundation

/// Loads a release detail cache-first, fetching from Discogs on a miss or once the cached copy
/// passes `Freshness.maximumAge`.
///
/// Tracklist, notes and the edition's country all arrive together from `GET /releases/{id}` —
/// there is no lighter call for any of them — so opening a record fetches once and keeps the
/// result. Another visit within six hours costs nothing against the rate limit. A stale copy that
/// cannot be refreshed, because Discogs is unreachable, is still shown.
@MainActor
@Observable
final class ReleaseDetailLoader {
    enum State: Equatable {
        case loading
        case loaded(ReleaseDetailSnapshot)
        case failed(String)
    }

    private(set) var state: State = .loading

    var snapshot: ReleaseDetailSnapshot? {
        if case .loaded(let snapshot) = state { return snapshot }
        return nil
    }

    private let services: AppServices
    /// The clock freshness is judged by. Injectable so tests can age a copy without waiting.
    private let now: () -> Date

    init(services: AppServices, now: @escaping () -> Date = Date.init) {
        self.services = services
        self.now = now
    }

    /// Shows the release, fetching it when there is no copy or the copy is past
    /// `Freshness.maximumAge`. A stale page stays on screen while it refreshes.
    func load(releaseID: Int) async {
        if let snapshot, Freshness.isFresh(snapshot.fetchedAt, now: now()) { return }
        if snapshot == nil { state = .loading }
        var cached = snapshot
        do {
            if let stored = try await services.store.releaseDetail(releaseID: releaseID) {
                cached = stored
            }
            if let cached, Freshness.isFresh(cached.fetchedAt, now: now()) {
                state = .loaded(cached)
                return
            }
            guard let client = services.client else {
                state = cached.map(State.loaded) ?? .failed("No Discogs token.")
                return
            }
            let release = try await client.release(id: releaseID)
            let fresh = try await services.store.upsertReleaseDetail(release)
            // The record page falls back to this image when the copy has no collection cover, so
            // the cover slot may hold the old one. When the copy does have a collection cover,
            // dropping the slot costs one download of that cover again.
            if let old = cached?.coverURL, old != fresh.coverURL {
                await services.imageCache.remove(releaseID: releaseID, kind: .cover)
            }
            state = .loaded(fresh)
        } catch is CancellationError {
            // The detail was dismissed before the fetch finished.
        } catch {
            state = cached.map(State.loaded) ?? .failed(error.localizedDescription)
        }
    }

    /// Keeps an open page inside `Freshness.maximumAge`: reloads when the shown copy falls due,
    /// and retries every `Freshness.retryInterval` while that fails.
    func keepFresh(releaseID: Int) async {
        while !Task.isCancelled {
            let wait = Freshness.timeUntilStale(snapshot?.fetchedAt, now: now())
            do {
                try await Task.sleep(for: .seconds(wait > 0 ? wait : Freshness.retryInterval))
            } catch {
                return
            }
            await load(releaseID: releaseID)
        }
    }
}
