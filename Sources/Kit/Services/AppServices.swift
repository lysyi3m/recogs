import DiscogsKit
import Foundation
import SwiftData

/// Single owner of the app's long-lived services.
///
/// One `DiscogsClient`, and therefore one `RateLimiter`, is shared by everything that talks to the
/// API, so the 60/min budget is accounted for in one place. The image cache is deliberately outside
/// that budget: the CDN does not share it.
@MainActor
@Observable
public final class AppServices {
    public let modelContainer: ModelContainer
    let store: CollectionStore
    let imageCache: ImageCache
    private let tokenStore: TokenStore

    /// Non-nil once a token is available. First-run setup sets it; until then the app is in its
    /// no-token state and browses whatever the cache already holds.
    private(set) var client: DiscogsClient?

    var hasToken: Bool { client != nil }

    public convenience init(modelContainer: ModelContainer) {
        self.init(modelContainer: modelContainer, tokenStore: TokenStore(), imageCache: ImageCache())
    }

    /// Full initializer, kept internal so the public surface does not expose the services it wires
    /// together. Tests use it to inject a temporary cache directory or Keychain account.
    init(
        modelContainer: ModelContainer,
        tokenStore: TokenStore = TokenStore(),
        imageCache: ImageCache = ImageCache()
    ) {
        self.modelContainer = modelContainer
        self.tokenStore = tokenStore
        self.imageCache = imageCache
        self.store = CollectionStore(modelContainer: modelContainer)
        self.client = (try? tokenStore.read()).flatMap { $0 }.map(Self.makeClient)
    }

    nonisolated public static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([CachedCollectionItem.self, CachedReleaseDetail.self, CachedFolder.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Validates a token against `/oauth/identity` before storing it, so a typo never reaches the
    /// Keychain.
    @discardableResult
    func signIn(token: String) async throws -> Identity {
        let candidate = Self.makeClient(token: token)
        let identity = try await candidate.identity()
        try tokenStore.save(token)
        client = candidate
        return identity
    }

    func signOut() throws {
        try tokenStore.delete()
        client = nil
    }

    func makeSyncer() -> CollectionSyncer? {
        guard let client else { return nil }
        return CollectionSyncer(client: client, store: store, imageCache: imageCache)
    }

    private static func makeClient(token: String) -> DiscogsClient {
        DiscogsClient(
            token: token,
            configuration: DiscogsConfiguration(userAgent: DiscogsUserAgent.value)
        )
    }
}
