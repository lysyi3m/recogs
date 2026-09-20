import Foundation
import Testing
@testable import DiscogsKit

@Suite("RateLimiter")
struct RateLimiterTests {
    private func response(limit: String?, used: String?, remaining: String?, status: Int = 200) throws -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let limit { headers["X-Discogs-Ratelimit"] = limit }
        if let used { headers["X-Discogs-Ratelimit-Used"] = used }
        if let remaining { headers["X-Discogs-Ratelimit-Remaining"] = remaining }
        return try #require(HTTPURLResponse(
            url: URL(string: "https://api.discogs.com/oauth/identity")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
    }

    @Test("Rate-limit headers are absorbed")
    func absorbsHeaders() async throws {
        let limiter = RateLimiter(limit: 60, safetyMargin: 5)
        await limiter.update(from: try response(limit: "60", used: "12", remaining: "48"))

        let state = await limiter.state
        #expect(state.limit == 60)
        #expect(state.used == 12)
        #expect(state.remaining == 48)
    }

    @Test("A response missing the headers leaves the previous state intact")
    func toleratesMissingHeaders() async throws {
        let limiter = RateLimiter(limit: 60, safetyMargin: 5)
        await limiter.update(from: try response(limit: "60", used: "1", remaining: "59"))
        await limiter.update(from: try response(limit: nil, used: nil, remaining: nil))

        let state = await limiter.state
        #expect(state.remaining == 59)
    }

    @Test("Requests inside the budget are not delayed")
    func fastPath() async throws {
        let limiter = RateLimiter(limit: 60, safetyMargin: 5)
        let start = ContinuousClock.now
        for _ in 0..<10 { try await limiter.waitForSlot() }
        let elapsed = ContinuousClock.now - start

        #expect(elapsed < .milliseconds(250))
        let state = await limiter.state
        #expect(state.requestsInWindow == 10)
    }

    @Test("Local budget stops at limit minus safety margin")
    func budgetHoldsBackTheMargin() async throws {
        let limiter = RateLimiter(limit: 10, safetyMargin: 4)
        for _ in 0..<6 { try await limiter.waitForSlot() }

        // The 7th slot would exceed limit - margin, so it must wait for the window to roll.
        let task = Task { try await limiter.waitForSlot() }
        try await Task.sleep(for: .milliseconds(200))
        let state = await limiter.state
        #expect(state.requestsInWindow == 6, "the extra request is parked, not recorded")
        task.cancel()
    }

    @Test("Backoff grows exponentially and honours Retry-After")
    func backoffDelay() async {
        let limiter = RateLimiter(limit: 60, safetyMargin: 5, baseBackoff: 1, maximumBackoff: 60)

        let first = await limiter.backoffDelay(retryAfter: nil, attempt: 0)
        let third = await limiter.backoffDelay(retryAfter: nil, attempt: 2)
        #expect(first >= 0.8 && first <= 1.2)
        #expect(third >= 3.2 && third <= 4.8)

        let honoured = await limiter.backoffDelay(retryAfter: 30, attempt: 0)
        #expect(honoured == 30, "a longer Retry-After wins over the computed delay")

        let capped = await limiter.backoffDelay(retryAfter: nil, attempt: 20)
        #expect(capped <= 60)
    }
}
