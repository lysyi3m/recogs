import Foundation

/// How old cached Discogs data may get before it is refreshed.
///
/// The Discogs API Terms of Use forbid displaying Content "more than six (6) hours older than the
/// information on Our online properties". Collection data, release details and cover art all count
/// as Content, so each is refreshed once it passes this age. Offline, the cache keeps showing with
/// its age on screen, and refreshes as soon as Discogs is reachable again.
enum Freshness {
    static let maximumAge: TimeInterval = 6 * 60 * 60

    /// How long to wait before trying again after a refresh that failed, usually because Discogs
    /// was unreachable.
    static let retryInterval: TimeInterval = 15 * 60

    /// A date in the future is not fresh: after the clock moves back it would otherwise hold off
    /// every refresh until the clock caught up.
    static func isFresh(_ date: Date?, now: Date = .now) -> Bool {
        guard let date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < maximumAge
    }

    /// Seconds until data fetched at `date` goes stale; zero when it already is.
    static func timeUntilStale(_ date: Date?, now: Date = .now) -> TimeInterval {
        guard let date, isFresh(date, now: now) else { return 0 }
        return maximumAge - now.timeIntervalSince(date)
    }
}
