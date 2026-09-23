import Foundation
import Testing
@testable import RecogsKit

@Suite("Freshness")
struct FreshnessTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Data inside six hours is fresh, and data past it is not")
    func sixHourBoundary() {
        #expect(Freshness.isFresh(now.addingTimeInterval(-(6 * 3600 - 60)), now: now))
        #expect(!Freshness.isFresh(now.addingTimeInterval(-(6 * 3600 + 60)), now: now))
    }

    @Test("Data that was never fetched is never fresh")
    func missingDateIsStale() {
        #expect(!Freshness.isFresh(nil, now: now))
    }
}
