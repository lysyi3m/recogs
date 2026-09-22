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
        let resolved = directory ?? Self.defaultDirectory()
        if directory == nil { Self.migrateFromCachesDirectory(into: resolved) }
        self.directory = resolved
        self.session = session
        self.maximumConcurrentDownloads = max(maximumConcurrentDownloads, 1)
    }

    /// Application Support, not Caches.
    ///
    /// The collection is meant to stay browsable offline, and a wall of placeholder tiles is not
    /// browsable. `Library/Caches` is purgeable by definition — the system may reclaim it whenever
    /// it likes, which is exactly when an offline user would notice. The art is regenerable in
    /// principle but not while the device has no network, so it belongs in Application Support,
    /// excluded from backup because it can always be downloaded again.
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "Recogs/Images", directoryHint: .isDirectory)
    }

    /// Moves art left behind in the old Caches location, so an upgrade does not silently re-download
    /// every cover. Runs once: the old directory is gone afterwards.
    static func migrateFromCachesDirectory(into directory: URL) {
        let manager = FileManager.default
        guard let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let legacy = caches.appending(path: "Recogs/Images", directoryHint: .isDirectory)
        guard manager.fileExists(atPath: legacy.path) else { return }

        if manager.fileExists(atPath: directory.path) {
            // Both exist, so merge rather than clobber what is already in the new location.
            let contents = (try? manager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
            for kind in contents {
                let destination = directory.appending(path: kind.lastPathComponent, directoryHint: .isDirectory)
                try? manager.createDirectory(at: destination, withIntermediateDirectories: true)
                let files = (try? manager.contentsOfDirectory(at: kind, includingPropertiesForKeys: nil)) ?? []
                for file in files {
                    try? manager.moveItem(at: file, to: destination.appending(path: file.lastPathComponent))
                }
            }
            try? manager.removeItem(at: legacy)
        } else {
            try? manager.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.moveItem(at: legacy, to: directory)
        }
    }

    /// Keeps the art out of iCloud and iTunes backups. It is several megabytes of data Discogs can
    /// serve again, so backing it up wastes the user's storage rather than protecting anything.
    private func excludeFromBackup() {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
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
            // An undecodable file is worse than none: it counts as cached forever. Drop it so the
            // next request downloads again.
            try? FileManager.default.removeItem(at: url)
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
        // A 200 does not mean an image. CDNs answer with HTML error pages, empty bodies and
        // truncated responses, and nothing here is ever re-fetched — so anything that is not a
        // complete image must be rejected before it reaches the cache.
        guard Self.isCompleteImage(data) else { throw CacheError.notAnImage }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        excludeFromBackup()
        // Write via a temporary file so an interrupted download never leaves a truncated image
        // that the cache would then treat as complete and never re-fetch.
        let temporary = destination.deletingLastPathComponent()
            .appending(path: UUID().uuidString, directoryHint: .notDirectory)
        try data.write(to: temporary, options: .atomic)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        } catch {
            // Swallowing this would return a path with no file behind it and leak the temporary.
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return destination
    }

    /// Whether `data` is an image the system can decode in full.
    ///
    /// The container checks are cheap early-outs: an HTML body has no image type and an empty one
    /// has no frames. They are not sufficient on their own — a source built from a complete `Data`
    /// reports `statusComplete` even when the pixel data is truncated — so the image is decoded
    /// once to be sure. That cost is paid on first download only, and never re-fetching makes a
    /// corrupt file expensive to accept.
    nonisolated static func isCompleteImage(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0
        else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
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
