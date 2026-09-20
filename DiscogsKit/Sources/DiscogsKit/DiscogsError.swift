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

extension DiscogsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized(let message):
            return message ?? "Discogs rejected the token."
        case .notFound(let message):
            return message ?? "Not found."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited by Discogs. Retry in \(Int(retryAfter.rounded()))s."
            }
            return "Rate limited by Discogs."
        case .http(let status, let message):
            return message ?? "Discogs returned HTTP \(status)."
        case .decoding:
            return "Could not decode the Discogs response."
        case .transport(let underlying):
            return underlying.localizedDescription
        case .invalidURL:
            return "Could not build a valid request URL."
        }
    }
}

/// Discogs returns `{"message": "..."}` on most errors.
struct DiscogsErrorPayload: Decodable {
    let message: String
}
