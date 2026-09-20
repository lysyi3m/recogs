import DiscogsKit
import Foundation

/// Loads a release detail cache-first, fetching from Discogs only on a miss.
///
/// The spec's rule is that a tracklist is fetched once and kept, so a second visit to a record
/// costs nothing against the rate limit.
@MainActor
@Observable
final class ReleaseDetailLoader {
    enum State {
        case loading
        case loaded(ReleaseDetailSnapshot)
        case failed(String)
    }

    private(set) var state: State = .loading

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func load(releaseID: Int) async {
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
