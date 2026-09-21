import Foundation
import Testing
@testable import DiscogsKit

/// Serves canned responses and counts how many times each path was requested.
final class CountingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var body = Data()
    private static let lock = NSLock()

    static func configure(status: Int, body: Data) {
        lock.withLock {
            counts = [:]
            self.status = status
            self.body = body
        }
    }

    static func count(forMethod method: String) -> Int {
        lock.withLock { counts[method] ?? 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "?"
        let (status, body) = Self.lock.withLock { () -> (Int, Data) in
            Self.counts[method, default: 0] += 1
            return (Self.status, Self.body)
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Retry policy", .serialized)
struct RetryPolicyTests {
    private func makeClient(maxRetries: Int = 3) -> DiscogsClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingProtocol.self]
        return DiscogsClient(
            token: "test",
            configuration: DiscogsConfiguration(
                userAgent: "Test/1.0 +test",
                rateLimitSafetyMargin: 0,
                maxRetries: maxRetries
            ),
            session: URLSession(configuration: configuration),
            rateLimiter: RateLimiter(limit: 60, safetyMargin: 0, baseBackoff: 0.01, maximumBackoff: 0.02)
        )
    }

    @Test("A 5xx never retries an add, because Discogs may already have applied it")
    func addIsNotRetriedOnServerError() async throws {
        CountingProtocol.configure(status: 503, body: Data("{}".utf8))
        let client = makeClient()

        await #expect(throws: DiscogsError.self) {
            try await client.addToCollection(user: "emil", folderID: 1, releaseID: 1)
        }
        #expect(CountingProtocol.count(forMethod: "POST") == 1, "an add must be sent exactly once")
    }

    @Test("A 5xx does retry a read, which is safe to repeat")
    func getIsRetriedOnServerError() async throws {
        CountingProtocol.configure(status: 503, body: Data("{}".utf8))
        let client = makeClient(maxRetries: 2)

        await #expect(throws: DiscogsError.self) { try await client.identity() }
        #expect(CountingProtocol.count(forMethod: "GET") == 3, "the first attempt plus two retries")
    }

    @Test("A 5xx retries a delete: removing the same instance twice is harmless")
    func deleteIsRetriedOnServerError() async throws {
        CountingProtocol.configure(status: 503, body: Data("{}".utf8))
        let client = makeClient(maxRetries: 2)

        await #expect(throws: DiscogsError.self) {
            try await client.removeFromCollection(user: "emil", folderID: 1, releaseID: 1, instanceID: 2)
        }
        #expect(CountingProtocol.count(forMethod: "DELETE") == 3)
    }

    @Test("A successful add is sent once and returns its instance id")
    func successfulAdd() async throws {
        CountingProtocol.configure(status: 201, body: Data(#"{"instance_id": 99}"#.utf8))
        let client = makeClient()

        let addition = try await client.addToCollection(user: "emil", folderID: 1, releaseID: 1)
        #expect(addition.instanceID == 99)
        #expect(CountingProtocol.count(forMethod: "POST") == 1)
    }
}
