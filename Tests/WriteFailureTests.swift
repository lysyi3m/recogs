import DiscogsKit
import Foundation
import Testing
@testable import RecogsKit

@Suite("Write failures", .serialized)
@MainActor
struct WriteFailureTests {
    /// Intercepts `URLSession.shared`, which is what `AppServices` builds its client on. Fails the
    /// write once, then lets it through, so a retry has something different to find.
    final class FlakyProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var failNextWrite = true
        nonisolated(unsafe) static var writeAttempts = 0
        private static let lock = NSLock()

        static func reset() {
            lock.withLock {
                failNextWrite = true
                writeAttempts = 0
            }
        }

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "api.discogs.com"
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let isWrite = request.httpMethod == "DELETE" || request.httpMethod == "POST"
            let status: Int
            let body: String
            if request.url?.path.hasSuffix("/oauth/identity") == true {
                status = 200
                body = #"{"id":1,"username":"tester","resource_url":"https://api.discogs.com"}"#
            } else if isWrite {
                let shouldFail = Self.lock.withLock { () -> Bool in
                    Self.writeAttempts += 1
                    defer { Self.failNextWrite = false }
                    return Self.failNextWrite
                }
                status = shouldFail ? 403 : 204
                body = shouldFail ? #"{"message":"Nope."}"# : ""
            } else {
                status = 200
                body = "{}"
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func makeServices() throws -> (services: AppServices, tokenStore: TokenStore) {
        let tokenStore = TokenStore(service: "com.mlkshkvch.recogs.tests.\(UUID().uuidString)")
        try tokenStore.save("test-token")
        let services = AppServices(
            modelContainer: try AppServices.makeModelContainer(inMemory: true),
            tokenStore: tokenStore,
            imageCache: ImageCache(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))
        )
        return (services, tokenStore)
    }

    private func makeItem(instanceID: Int) throws -> CollectionItem {
        let json = """
        {
          "id": 500, "instance_id": \(instanceID), "folder_id": 1, "rating": 0,
          "date_added": "2019-05-06T18:32:50-07:00",
          "basic_information": {
            "id": 500, "title": "Remain In Light", "year": 1980,
            "artists": [{ "name": "Talking Heads", "join": "" }],
            "labels": [], "formats": [], "genres": [], "styles": []
          }
        }
        """
        return try DiscogsClient.makeDecoder().decode(CollectionItem.self, from: Data(json.utf8))
    }

    @Test("A rejected removal offers a retry that actually removes the copy")
    func failedRemoveRetries() async throws {
        FlakyProtocol.reset()
        URLProtocol.registerClass(FlakyProtocol.self)
        defer { URLProtocol.unregisterClass(FlakyProtocol.self) }

        let (services, tokenStore) = try makeServices()
        defer { try? tokenStore.delete() }
        try await services.store.upsert([try makeItem(instanceID: 111)])

        let editor = services.makeEditor()
        #expect(await editor.remove(instanceID: 111) == false)

        // The copy is back, and the failure carries the way to try again.
        #expect(try await services.store.itemCount() == 1, "a rejected delete rolls back")
        let failure = try #require(editor.failure)
        #expect(failure.message.isEmpty == false)

        await failure.retry()

        #expect(FlakyProtocol.writeAttempts == 2, "the retry must reach Discogs again")
        #expect(try await services.store.itemCount() == 0, "the retry must remove the copy")
        #expect(editor.failure == nil, "a successful retry clears the failure")
    }
}
