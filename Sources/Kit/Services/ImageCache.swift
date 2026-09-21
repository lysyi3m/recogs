import Foundation
import ImageIO
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// Permanent on-disk cache for cover art, keyed by release id.
///
/// Thumbs and full-resolution covers are stored separately so the grid can be usable long before
/// any full-res image is fetched. Nothing is ever evicted or re-fetched: a release's art does not
/// change, and re-downloading is the one cost worth avoiding on a metered API.
///
/// Image requests do not pass through `RateLimiter`. Measured against the live API, `i.discogs.com`
/// returns no `X-Discogs-Ratelimit*` headers and does not move the counter, so the CDN has its own
/// budget. Concurrency is capped instead, to avoid opening dozens of sockets during a first sync.
actor ImageCache {
    enum Kind: String, Sendable {
        /// ~150px, embedded in every collection item.
        case thumb
        /// ~500px+, fetched lazily when a record detail opens.
        case cover
    }

    enum CacheError: Error, LocalizedError {
        case badResponse(status: Int)
        case notAnImage

        var errorDescription: String? {
            switch self {
            case .badResponse(let status): return "Image request failed with HTTP \(status)."
            case .notAnImage: return "The downloaded file was not a decodable image."
            }
        }
    }

    private let directory: URL
    private let session: URLSession
    private let maximumConcurrentDownloads: Int

    private var activeDownloads = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Coalesces concurrent requests for the same file so a cover is fetched once, not once per view.
    private var inFlight: [URL: Task<URL, any Error>] = [:]

    init(
        directory: URL? = nil,
        session: URLSession = .shared,
        maximumConcurrentDownloads: Int = 6
    ) {
        self.directory = directory ?? Self.defaultDirectory()
        self.session = session
        self.maximumConcurrentDownloads = max(maximumConcurrentDownloads, 1)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "Recogs/Images", directoryHint: .isDirectory)
    }

    func fileURL(releaseID: Int, kind: Kind) -> URL {
        directory
            .appending(path: kind.rawValue, directoryHint: .isDirectory)
            .appending(path: "\(releaseID).img", directoryHint: .notDirectory)
    }

    func isCached(releaseID: Int, kind: Kind) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(releaseID: releaseID, kind: kind).path)
    }

    /// Returns the local file for a release's art, downloading it once if it is not cached yet.
    ///
    /// Keyed by release and kind, deliberately not by URL. Discogs serves the same artwork under
    /// several resized URLs — `basic_information.cover_image` is a 600px fit, the release's own
    /// primary image a smaller one — all derived from one source file. Re-fetching because the URL
    /// changed would spend a request to replace an image with the same picture, sometimes smaller.
    @discardableResult
    func localURL(releaseID: Int, kind: Kind, remoteURL: URL) async throws -> URL {
        let destination = fileURL(releaseID: releaseID, kind: kind)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }

        if let existing = inFlight[destination] { return try await existing.value }

        let task = Task<URL, any Error> {
            try await withConcurrencyLimit {
                try await download(remoteURL, to: destination)
            }
        }
        inFlight[destination] = task
        defer { inFlight[destination] = nil }
        return try await task.value
    }

    /// Decodes a cached image, downsampled so a grid of hundreds of covers stays memory-bounded.
    func image(releaseID: Int, kind: Kind, remoteURL: URL, maximumPixelSize: CGFloat) async throws -> PlatformImage {
        let url = try await localURL(releaseID: releaseID, kind: kind, remoteURL: remoteURL)
        guard let image = Self.downsample(at: url, maximumPixelSize: maximumPixelSize) else {
            throw CacheError.notAnImage
        }
        return image
    }

    struct Statistics: Sendable, Hashable {
        var fileCount: Int
        var byteCount: Int
    }

    /// What is on disk. Used by diagnostics, not by any eviction policy — there is none.
    func statistics() -> Statistics {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return Statistics(fileCount: 0, byteCount: 0) }

        var statistics = Statistics(fileCount: 0, byteCount: 0)
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            statistics.fileCount += 1
            statistics.byteCount += values?.fileSize ?? 0
        }
        return statistics
    }

    func diskUsage() -> Int { statistics().byteCount }

    func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Downloading

    private func download(_ remoteURL: URL, to destination: URL) async throws -> URL {
        var request = URLRequest(url: remoteURL)
        request.setValue(DiscogsUserAgent.value, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CacheError.badResponse(status: http.statusCode)
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Write via a temporary file so an interrupted download never leaves a truncated image
        // that the cache would then treat as complete and never re-fetch.
        let temporary = destination.deletingLastPathComponent()
            .appending(path: UUID().uuidString, directoryHint: .notDirectory)
        try data.write(to: temporary, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        return destination
    }

    private func withConcurrencyLimit<T>(_ work: () async throws -> T) async throws -> T {
        while activeDownloads >= maximumConcurrentDownloads {
            await withCheckedContinuation { waiters.append($0) }
        }
        activeDownloads += 1
        defer {
            activeDownloads -= 1
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        return try await work()
    }

    // MARK: - Decoding

    nonisolated static func downsample(at url: URL, maximumPixelSize: CGFloat) -> PlatformImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maximumPixelSize, 1),
        ] as [CFString: Any] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: .zero)
        #endif
    }
}
