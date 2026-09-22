import DiscogsKit
import Foundation

/// Runs release searches so that only the newest one can change what is on screen.
///
/// Submitting repeatedly, or editing mid-request, puts several requests in flight with no ordering
/// between them, so a slower earlier response could replace newer results. Each search takes a new
/// `generation`, and a response is applied only while its generation is still current.
@MainActor
@Observable
final class ReleaseSearchController {
    enum State: Equatable {
        case idle
        case searching
        case loaded(total: Int)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var results: [SearchResult] = []

    /// Performs one search. Injected so the ordering can be tested without a network.
    private let performSearch: (String) async throws -> SearchPage

    /// Increments per search; a response may only be applied if its generation is still current.
    private var generation = 0
    private var task: Task<Void, Never>?

    init(performSearch: @escaping (String) async throws -> SearchPage) {
        self.performSearch = performSearch
    }

    convenience init(client: DiscogsClient, perPage: Int = 50) {
        self.init { query in
            try await client.searchReleases(query: query, perPage: perPage)
        }
    }

    var isSearching: Bool { state == .searching }

    func search(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        task?.cancel()
        generation += 1
        let generation = generation
        state = .searching

        task = Task { [weak self] in
            await self?.run(query, generation: generation)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func run(_ query: String, generation: Int) async {
        do {
            let page = try await performSearch(query)
            // A superseded search must not write over the newer one's results.
            guard generation == self.generation else { return }
            results = page.results
            state = .loaded(total: page.pagination.items)
        } catch is CancellationError {
            // A newer search owns the state now.
        } catch {
            guard generation == self.generation else { return }
            results = []
            state = .failed(error.localizedDescription)
        }
    }
}
