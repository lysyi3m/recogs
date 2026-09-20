import Foundation

/// Static configuration for a `DiscogsClient`.
///
/// The Discogs API requires a `User-Agent` that uniquely identifies the client and carries a
/// contact. Generic agents are throttled harder, so `contact` has no sensible library default and
/// callers are expected to set it for the shipping app.
public struct DiscogsConfiguration: Sendable {
    /// API root. Discogs API v2.
    public var baseURL: URL

    /// Value sent as `User-Agent`, e.g. `Recogs/1.0 +https://example.com`.
    public var userAgent: String

    /// Page size for paginated endpoints. Discogs caps this at 100.
    public var perPage: Int

    /// Requests held back from the advertised rate limit, so a burst never lands exactly on the cap.
    public var rateLimitSafetyMargin: Int

    /// Attempts made after the first failure for retryable responses (429 and 5xx).
    public var maxRetries: Int

    public static let maximumPerPage = 100

    public init(
        baseURL: URL = URL(string: "https://api.discogs.com")!,
        userAgent: String,
        perPage: Int = DiscogsConfiguration.maximumPerPage,
        rateLimitSafetyMargin: Int = 5,
        maxRetries: Int = 3
    ) {
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.perPage = min(max(perPage, 1), DiscogsConfiguration.maximumPerPage)
        self.rateLimitSafetyMargin = max(rateLimitSafetyMargin, 0)
        self.maxRetries = max(maxRetries, 0)
    }

    /// Contact published in the `User-Agent`, so Discogs can reach the app's author.
    public static let contact = "https://github.com/lysyi3m/recogs"

    /// Builds the required `User-Agent` for a given app version and contact.
    public static func userAgent(
        appVersion: String = "1.0",
        contact: String = DiscogsConfiguration.contact
    ) -> String {
        "Recogs/\(appVersion) +\(contact)"
    }
}

/// Well-known Discogs folder identifiers.
public enum DiscogsFolder {
    /// Pseudo-folder spanning every item in the collection. Read-only: adds must target a real folder.
    public static let all = 0
    /// The default real folder. v1 adds land here.
    public static let uncategorized = 1
}
