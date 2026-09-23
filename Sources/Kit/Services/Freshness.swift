import Foundation

/// How old cached Discogs data may get before it is refreshed.
///
/// The Discogs API Terms of Use forbid displaying Content "more than six (6) hours older than the
/// information on Our online properties". Collection data, release details and cover art all count
/// as Content, so each is refreshed once it passes this age. Offline, the cache keeps showing with
/// its age on screen, and refreshes as soon as Discogs is reachable again.
enum Freshness {
    static let maximumAge: TimeInterval = 6 * 60 * 60

    static func isFresh(_ date: Date?, now: Date = .now) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) < maximumAge
    }
}
