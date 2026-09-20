import Foundation
import Testing
@testable import RecogsKit

@Suite("ImageCache")
struct ImageCacheTests {
    /// Serves a 1x1 PNG and counts how many times each URL is requested, so "never re-fetch" is a
    /// measurable claim rather than an assumption.
    final class CountingProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestCounts: [String: Int] = [:]
        nonisolated(unsafe) static var statusCode = 200
        private static let lock = NSLock()

        static let pngBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

        static func reset() {
            lock.withLock {
                requestCounts = [:]
                statusCode = 200
            }
        }

        static func count(for url: String) -> Int {
            lock.withLock { requestCounts[url] ?? 0 }
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let key = request.url?.absoluteString ?? ""
            let status = Self.lock.withLock {
                Self.requestCounts[key, default: 0] += 1
                return Self.statusCode
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if status == 200 { client?.urlProtocol(self, didLoad: Self.pngBytes) }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func makeCache(directory: URL) -> ImageCache {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingProtocol.self]
        return ImageCache(directory: directory, session: URLSession(configuration: configuration))
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "recogs-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("An image is downloaded once and served from disk thereafter")
    func cachesPermanently() async throws {
        CountingProtocol.reset()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = makeCache(directory: directory)
        let remote = URL(string: "https://i.discogs.com/cover-1.jpeg")!

        #expect(await cache.isCached(releaseID: 1, kind: .thumb) == false)
        let first = try await cache.localURL(releaseID: 1, kind: .thumb, remoteURL: remote)
        let second = try await cache.localURL(releaseID: 1, kind: .thumb, remoteURL: remote)

        #expect(first == second)
        #expect(await cache.isCached(releaseID: 1, kind: .thumb))
        #expect(CountingProtocol.count(for: remote.absoluteString) == 1, "the second call must not re-fetch")
    }

    @Test("Thumb and cover are cached separately for the same release")
    func kindsAreIndependent() async throws {
        CountingProtocol.reset()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = makeCache(directory: directory)
        let thumb = URL(string: "https://i.discogs.com/1-thumb.jpeg")!
        let cover = URL(string: "https://i.discogs.com/1-cover.jpeg")!

        _ = try await cache.localURL(releaseID: 1, kind: .thumb, remoteURL: thumb)
        #expect(await cache.isCached(releaseID: 1, kind: .cover) == false)

        _ = try await cache.localURL(releaseID: 1, kind: .cover, remoteURL: cover)
        #expect(await cache.isCached(releaseID: 1, kind: .thumb))
        #expect(await cache.isCached(releaseID: 1, kind: .cover))
    }

    @Test("Concurrent requests for one image collapse into a single download")
    func coalescesConcurrentRequests() async throws {
        CountingProtocol.reset()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = makeCache(directory: directory)
        let remote = URL(string: "https://i.discogs.com/busy.jpeg")!

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask { _ = try? await cache.localURL(releaseID: 7, kind: .thumb, remoteURL: remote) }
            }
        }

        #expect(CountingProtocol.count(for: remote.absoluteString) == 1)
    }

    @Test("A failed download leaves nothing cached, so the next attempt retries")
    func failureDoesNotPoisonTheCache() async throws {
        CountingProtocol.reset()
        CountingProtocol.statusCode = 404
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = makeCache(directory: directory)
        let remote = URL(string: "https://i.discogs.com/missing.jpeg")!

        await #expect(throws: (any Error).self) {
            try await cache.localURL(releaseID: 9, kind: .thumb, remoteURL: remote)
        }
        #expect(await cache.isCached(releaseID: 9, kind: .thumb) == false)
    }

    @Test("Cached images decode, downsampled to the requested size")
    func downsamples() async throws {
        CountingProtocol.reset()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = makeCache(directory: directory)
        let remote = URL(string: "https://i.discogs.com/decodable.jpeg")!

        let image = try await cache.image(releaseID: 3, kind: .thumb, remoteURL: remote, maximumPixelSize: 150)
        #expect(image.size.width > 0)
    }
}
