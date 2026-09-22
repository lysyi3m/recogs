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
        nonisolated(unsafe) static var writeAttempts = 0
        /// How many writes fail before one is allowed through. A DELETE that meets a 5xx is
        /// retried by the client, so a persistent failure needs every attempt to fail.
        nonisolated(unsafe) static var writesToFail = 1
        /// What a failing write answers with. 403 is a definite rejection; 503 is not.
        nonisolated(unsafe) static var failureStatus = 403
        private static let lock = NSLock()

        static func reset(failureStatus: Int = 403, writesToFail: Int = 1) {
            lock.withLock {
                writeAttempts = 0
                self.failureStatus = failureStatus
                self.writesToFail = writesToFail
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
                    return Self.writeAttempts <= Self.writesToFail
                }
                status = shouldFail ? Self.lock.withLock({ Self.failureStatus }) : 204
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

    @Test("A removal Discogs has already applied is not undone")
    func removeOfMissingCopyIsSuccess() async throws {
        FlakyProtocol.reset(failureStatus: 404)
        URLProtocol.registerClass(FlakyProtocol.self)
        defer { URLProtocol.unregisterClass(FlakyProtocol.self) }

        let (services, tokenStore) = try makeServices()
        defer { try? tokenStore.delete() }
        try await services.store.upsert([try makeItem(instanceID: 111)])

        // 404 means Discogs has no such copy — which is exactly what the user asked for. Restoring
        // the row would resurrect a record that is already gone upstream.
        let editor = services.makeEditor()
        #expect(await editor.remove(instanceID: 111) == true)
        #expect(try await services.store.itemCount() == 0)
        #expect(editor.failure == nil)
    }

    @Test("An unconfirmed removal is not rolled back, and offers no retry")
    func unconfirmedRemoveIsNotRolledBack() async throws {
        // 503 after the retries: the delete may well have been applied before it failed.
        FlakyProtocol.reset(failureStatus: 503, writesToFail: .max)
        URLProtocol.registerClass(FlakyProtocol.self)
        defer { URLProtocol.unregisterClass(FlakyProtocol.self) }

        let (services, tokenStore) = try makeServices()
        defer { try? tokenStore.delete() }
        try await services.store.upsert([try makeItem(instanceID: 111)])

        let editor = services.makeEditor()
        #expect(await editor.remove(instanceID: 111) == false)
        let failure = try #require(editor.failure)
        #expect(failure.retry == nil, "retrying an unconfirmed write can duplicate or mislead")
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
        let retry = try #require(failure.retry, "a definite rejection is safe to retry")

        await retry()

        #expect(FlakyProtocol.writeAttempts == 2, "the retry must reach Discogs again")
        #expect(try await services.store.itemCount() == 0, "the retry must remove the copy")
        #expect(editor.failure == nil, "a successful retry clears the failure")
    }
}
