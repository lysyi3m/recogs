import DiscogsKit
import Foundation

/// Answers the spec's open question: do Discogs CDN image loads count against the 60/min API limit?
///
/// Measures `X-Discogs-Ratelimit-Used` before and after an image fetch. If the CDN shares the API
/// budget, the counter moves by more than the two API calls that bracket the fetch.
enum CDNCheck {
    static func run(client: DiscogsClient, identity: Identity) async throws {
        print("== CDN rate-limit check ==")

        let page = try await client.collectionPage(user: identity.username, page: 1, perPage: 1)
        guard let thumb = page.releases.first?.basicInformation.thumb,
              let thumbURL = URL(string: thumb) else {
            print("  skipped: no thumb URL in the first collection item")
            return
        }

        let before = await client.rateLimiter.state
        print("  before image fetch: used=\(before.used.map(String.init) ?? "?") remaining=\(before.remaining.map(String.init) ?? "?")")

        var request = URLRequest(url: thumbURL)
        request.setValue(client.configuration.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("  image fetch returned a non-HTTP response")
            return
        }

        let cdnHeaders = ["X-Discogs-Ratelimit", "X-Discogs-Ratelimit-Used", "X-Discogs-Ratelimit-Remaining"]
            .compactMap { name in http.value(forHTTPHeaderField: name).map { "\(name)=\($0)" } }
        print("  image: HTTP \(http.statusCode), \(data.count) bytes from \(thumbURL.host() ?? "?")")
        print("  image rate-limit headers: \(cdnHeaders.isEmpty ? "none" : cdnHeaders.joined(separator: " "))")

        _ = try await client.collectionPage(user: identity.username, page: 1, perPage: 1)
        let after = await client.rateLimiter.state
        print("  after image fetch:  used=\(after.used.map(String.init) ?? "?") remaining=\(after.remaining.map(String.init) ?? "?")")

        guard let usedBefore = before.used, let usedAfter = after.used else {
            print("  inconclusive: the server did not report a used count")
            return
        }
        let delta = usedAfter - usedBefore
        // One API call brackets the image fetch on each side; only the trailing call lands between
        // the two readings, so a delta above 1 means the image consumed budget too.
        if delta <= 1 {
            print("  → CDN image loads do NOT count against the API limit (used +\(delta) for 1 API call)")
        } else {
            print("  → CDN image loads DO count against the API limit (used +\(delta) for 1 API call + 1 image)")
        }
    }
}
