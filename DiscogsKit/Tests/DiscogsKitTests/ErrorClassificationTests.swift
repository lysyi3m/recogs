import Foundation
import Testing
@testable import DiscogsKit

@Suite("Error classification")
struct ErrorClassificationTests {
    @Test("Connectivity failures are offline, not server errors")
    func offlineCodes() {
        let offline: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .dataNotAllowed, .timedOut, .internationalRoamingOff,
        ]
        for code in offline {
            let error = DiscogsError.transport(underlying: URLError(code))
            #expect(error.isOffline, "\(code) should read as offline")
            #expect(!error.isRateLimited)
            #expect(!error.isUnauthorized)
        }
    }

    @Test("A server failure is not mistaken for being offline")
    func serverErrorsAreNotOffline() {
        #expect(!DiscogsError.http(status: 500, message: nil).isOffline)
        #expect(!DiscogsError.transport(underlying: URLError(.badServerResponse)).isOffline)
        #expect(!DiscogsError.decoding(underlying: URLError(.cancelled)).isOffline)
    }

    @Test("Rate limiting and a rejected token are each distinguishable")
    func rateLimitAndAuth() {
        let rateLimited = DiscogsError.rateLimited(retryAfter: 30)
        #expect(rateLimited.isRateLimited)
        #expect(!rateLimited.isUnauthorized)

        let unauthorized = DiscogsError.unauthorized(message: nil)
        #expect(unauthorized.isUnauthorized)
        #expect(!unauthorized.isRateLimited)
    }

    @Test("Offline reads as a plain message rather than a raw URLError")
    func offlineMessage() throws {
        let message = try #require(DiscogsError.transport(underlying: URLError(.notConnectedToInternet)).errorDescription)
        #expect(message == "No connection to Discogs.")
    }

    @Test("A rate-limit message names the wait")
    func rateLimitMessage() throws {
        let message = try #require(DiscogsError.rateLimited(retryAfter: 30).errorDescription)
        #expect(message.contains("30"))
    }
}
