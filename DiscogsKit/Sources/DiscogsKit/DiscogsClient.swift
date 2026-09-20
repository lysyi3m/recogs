import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Async client for the Discogs API v2, authenticated with a Personal Access Token.
///
/// Every request goes through a shared `RateLimiter`, so several clients built from the same
/// limiter stay inside one budget. The token is held in memory only and is never logged.
public struct DiscogsClient: Sendable {
    public let configuration: DiscogsConfiguration
    public let rateLimiter: RateLimiter

    private let token: String
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        token: String,
        configuration: DiscogsConfiguration,
        session: URLSession = .shared,
        rateLimiter: RateLimiter? = nil
    ) {
        self.token = token
        self.configuration = configuration
        self.session = session
        self.rateLimiter = rateLimiter ?? RateLimiter(safetyMargin: configuration.rateLimitSafetyMargin)
        self.decoder = DiscogsClient.makeDecoder()
    }

    // MARK: - Identity

    /// `GET /oauth/identity` — resolves the username the token belongs to. Also the token check
    /// used by first-run setup.
    public func identity() async throws -> Identity {
        try await get(path: "/oauth/identity")
    }

    // MARK: - Folders

    /// `GET /users/{user}/collection/folders`
    public func folders(user: String) async throws -> [Folder] {
        let list: FolderList = try await get(path: "/users/\(escape(user))/collection/folders")
        return list.folders
    }

    // MARK: - Releases

    /// `GET /releases/{id}` — the full release, including tracklist and full-size images.
    public func release(id: Int) async throws -> Release {
        try await get(path: "/releases/\(id)")
    }

    // MARK: - Collection

    /// One page of `GET /users/{user}/collection/folders/{folder_id}/releases`.
    ///
    /// - Parameter page: 1-based, as Discogs numbers pages.
    public func collectionPage(
        user: String,
        folderID: Int = DiscogsFolder.all,
        page: Int = 1,
        perPage: Int? = nil,
        sort: CollectionSort? = nil,
        order: DiscogsSortOrder? = nil
    ) async throws -> CollectionPage {
        var query = [
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "per_page", value: String(perPage ?? configuration.perPage)),
        ]
        if let sort { query.append(URLQueryItem(name: "sort", value: sort.rawValue)) }
        if let order { query.append(URLQueryItem(name: "sort_order", value: order.rawValue)) }

        return try await get(
            path: "/users/\(escape(user))/collection/folders/\(folderID)/releases",
            query: query
        )
    }

    /// Streams the collection page by page, so a caller can render progressively during the first
    /// sync instead of waiting for the whole collection.
    public func collectionPages(
        user: String,
        folderID: Int = DiscogsFolder.all,
        perPage: Int? = nil,
        sort: CollectionSort? = nil,
        order: DiscogsSortOrder? = nil
    ) -> AsyncThrowingStream<CollectionPage, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var page = 1
                    while true {
                        try Task.checkCancellation()
                        let result = try await collectionPage(
                            user: user,
                            folderID: folderID,
                            page: page,
                            perPage: perPage,
                            sort: sort,
                            order: order
                        )
                        continuation.yield(result)
                        guard result.pagination.hasNextPage else { break }
                        page += 1
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Every item in the collection, paging until Discogs reports the last page.
    public func allCollectionItems(
        user: String,
        folderID: Int = DiscogsFolder.all,
        perPage: Int? = nil,
        sort: CollectionSort? = nil,
        order: DiscogsSortOrder? = nil
    ) async throws -> [CollectionItem] {
        var items: [CollectionItem] = []
        for try await page in collectionPages(
            user: user, folderID: folderID, perPage: perPage, sort: sort, order: order
        ) {
            items.append(contentsOf: page.releases)
        }
        return items
    }

    // MARK: - Request plumbing

    private func get<Response: Decodable>(
        path: String,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(path: path, query: query)
        let data = try await send(request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw DiscogsError.decoding(underlying: error)
        }
    }

    private func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw DiscogsError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw DiscogsError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Sends a request through the throttle, retrying 429 and 5xx with backoff.
    private func send(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            try await rateLimiter.waitForSlot()

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw DiscogsError.transport(underlying: error)
            }

            guard let http = response as? HTTPURLResponse else {
                throw DiscogsError.http(status: -1, message: "Response was not HTTP.")
            }
            await rateLimiter.update(from: http)

            switch http.statusCode {
            case 200...299:
                return data

            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
                guard attempt < configuration.maxRetries else {
                    throw DiscogsError.rateLimited(retryAfter: retryAfter)
                }
                try await rateLimiter.noteRateLimited(retryAfter: retryAfter, attempt: attempt)
                attempt += 1

            case 500...599:
                guard attempt < configuration.maxRetries else {
                    throw DiscogsError.http(status: http.statusCode, message: message(from: data))
                }
                try await rateLimiter.backOff(attempt: attempt)
                attempt += 1

            case 401, 403:
                throw DiscogsError.unauthorized(message: message(from: data))

            case 404:
                throw DiscogsError.notFound(message: message(from: data))

            default:
                throw DiscogsError.http(status: http.statusCode, message: message(from: data))
            }
        }
    }

    private func message(from data: Data) -> String? {
        try? JSONDecoder().decode(DiscogsErrorPayload.self, from: data).message
    }

    private func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    /// Decoder configured for Discogs payloads. Public so fixtures and previews can build models
    /// from recorded JSON without duplicating the date strategy.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Discogs sends ISO-8601 with a UTC offset, sometimes with fractional seconds.
        // ISO8601FormatStyle accepts both and, unlike ISO8601DateFormatter, is Sendable.
        let style = Date.ISO8601FormatStyle()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = try? style.parse(raw) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unrecognized date format: \(raw)"
                    )
                )
            }
            return date
        }
        return decoder
    }
}
