import DiscogsKit
import Foundation

/// Drives refreshes on behalf of the UI and publishes their state.
///
/// Kept separate from `AppServices` so views observe only what changes during a sync, and so the
/// progress and error handling live outside the view body.
@MainActor
@Observable
final class SyncController {
    private(set) var isSyncing = false
    private(set) var progress: CollectionSyncer.Progress?
    private(set) var errorMessage: String?
    private(set) var lastSummary: CollectionSyncer.Summary?
    /// Set when the last attempt never reached Discogs. The cache is still good, so this is a
    /// status rather than a failure.
    private(set) var isOffline = false
    private(set) var lastSyncedAt: Date?
    /// What the current operation is doing, for a progress label. Nil when idle.
    private(set) var activity: String?

    private unowned let services: AppServices
    /// The sync currently in flight, so work tied to the account can be stopped before the account
    /// goes away. Held because `runSync` deliberately shields the work from its caller.
    private var running: Task<Void, Never>?
    private static let lastSyncedKey = "lastSyncedAt"

    init(services: AppServices) {
        self.services = services
        lastSyncedAt = UserDefaults.standard.object(forKey: Self.lastSyncedKey) as? Date
    }

    /// A refresh on launch is wanted, but not on every window that opens seconds apart.
    var shouldSyncOnLaunch: Bool {
        guard services.hasToken else { return false }
        guard let lastSyncedAt else { return true }
        return Date().timeIntervalSince(lastSyncedAt) > 300
    }

    /// Runs a full refresh. Concurrent calls are ignored, so pull-to-refresh cannot stack syncs.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        activity = "Syncing…"
        defer {
            isSyncing = false
            activity = nil
            progress = nil
        }
        await runSync()
    }

    /// Runs a sync in a task of its own, so whoever asked for it cannot cancel it half-done.
    ///
    /// `.refreshable` cancels its task the moment the refresh control retracts, and a collection
    /// fetch that is cancelled mid-stream returns no pages at all. A refresh the user asked for is
    /// worth finishing. The task is kept so `cancelAndWait` can still stop it deliberately — being
    /// shielded from the caller is not the same as being unstoppable.
    private func runSync() async {
        let task = Task { await self.performSync() }
        running = task
        await task.value
        running = nil
    }

    /// Stops any sync in flight and waits for it to finish unwinding.
    ///
    /// Sign-out clears the token and the cache; a sync still running would otherwise write the old
    /// account's records back into the store behind it. A cancelled fetch throws rather than
    /// pruning, so nothing is half-applied.
    func cancelAndWait() async {
        guard let task = running else { return }
        task.cancel()
        await task.value
    }

    enum ResetError: LocalizedError {
        case noToken
        case unreachable(String)

        var errorDescription: String? {
            switch self {
            case .noToken:
                return "No Discogs token."
            case .unreachable(let reason):
                return "Nothing was deleted. \(reason)"
            }
        }
    }

    /// Clears the cache and rebuilds it.
    ///
    /// Discogs is checked first, because the cache is the only copy of the collection this device
    /// has. Clearing it and then failing to download would leave nothing to browse — exactly when
    /// the user is offline and the cache matters most.
    ///
    /// `isSyncing` covers the whole operation, including the gap between the cache emptying and
    /// the download starting — otherwise the grid flashes its empty state in that window.
    func resetAndResync() async throws {
        guard !isSyncing else { return }
        guard let client = services.client else { throw ResetError.noToken }

        isSyncing = true
        activity = "Checking connection…"
        defer {
            isSyncing = false
            activity = nil
            progress = nil
        }

        do {
            _ = try await client.identity()
        } catch {
            let reason = (error as? DiscogsError)?.localizedDescription ?? error.localizedDescription
            throw ResetError.unreachable(reason)
        }

        activity = "Clearing cache…"
        try await services.resetCache()
        activity = "Downloading collection…"
        // A failure here leaves an empty cache, so it is reported even when the cause is simply
        // being offline.
        await runSync()
        // On the collection screen being offline is a status line, not a failure: the cache is
        // intact and still browsable.
        if isOffline { errorMessage = nil }
    }

    private func performSync() async {
        guard let syncer = services.makeSyncer() else { return }
        errorMessage = nil

        do {
            lastSummary = try await syncer.sync { update in
                Task { @MainActor in self.progress = update }
            }
            isOffline = false
            lastSyncedAt = Date()
            UserDefaults.standard.set(lastSyncedAt, forKey: Self.lastSyncedKey)
        } catch is CancellationError {
            // The caller went away; not a failure worth surfacing.
        } catch {
            isOffline = (error as? DiscogsError)?.isOffline ?? false
            // Always recorded here. Callers for which being offline is merely a status clear it;
            // callers that have already destroyed something must not.
            errorMessage = error.localizedDescription
        }
    }
}
