import DiscogsKit

/// The one `User-Agent` the app presents, to both the API and the image CDN.
enum DiscogsUserAgent {
    static let value = DiscogsConfiguration.userAgent()
}
