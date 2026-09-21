import DiscogsKit
import Foundation

/// Loads a release detail cache-first, fetching from Discogs only on a miss.
///
/// Tracklist, notes and the pressing's country all arrive together from `GET /releases/{id}` —
/// there is no lighter call for any of them — so opening a record fetches once and keeps the
/// result. A second visit to the same record costs nothing against the rate limit.
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

    init(services: AppServices) {
        self.services = services
    }

    func load(releaseID: Int) async {
        if case .loaded = state { return }
        state = .loading
        do {
            if let cached = try await services.store.releaseDetail(releaseID: releaseID) {
                state = .loaded(cached)
                return
            }
            guard let client = services.client else {
                state = .failed("No Discogs token.")
                return
            }
            let release = try await client.release(id: releaseID)
            state = .loaded(try await services.store.upsertReleaseDetail(release))
        } catch is CancellationError {
            // The detail was dismissed before the fetch finished.
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
