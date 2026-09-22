import Foundation

public enum DiscogsError: Error, Sendable {
    /// The token was rejected (401) or lacks access to the resource (403).
    case unauthorized(message: String?)
    case notFound(message: String?)
    /// Rate limited and still failing after the configured retries.
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other non-2xx response.
    case http(status: Int, message: String?)
    case decoding(underlying: any Error)
    case transport(underlying: any Error)
    case invalidURL
}

extension DiscogsError {
    /// True when the request never reached Discogs. The app stays usable from cache in this state,
    /// so it is worth distinguishing from a server-side failure.
    public var isOffline: Bool {
        guard case .transport(let underlying) = self,
              let urlError = underlying as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dataNotAllowed, .timedOut, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    public var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    /// True when the token is missing, wrong, or revoked, so the fix is to re-enter it.
    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

extension DiscogsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized(let message):
            return message ?? "Discogs rejected the token."
        case .notFound(let message):
            return message ?? "Not found."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited by Discogs. Try again in \(Int(retryAfter.rounded()))s."
            }
            return "Rate limited by Discogs."
        case .http(let status, let message):
            return message ?? "Discogs returned HTTP \(status)."
        case .decoding:
            return "Couldn't read the Discogs response."
        case .transport:
            return isOffline
                ? "No connection to Discogs."
                : "Couldn't reach Discogs."

        case .invalidURL:
            return "Invalid request URL."
        }
    }
}

/// Discogs returns `{"message": "..."}` on most errors.
struct DiscogsErrorPayload: Decodable {
    let message: String
}
