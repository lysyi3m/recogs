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

    private let services: AppServices
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
        guard !isSyncing, let syncer = services.makeSyncer() else { return }

        isSyncing = true
        errorMessage = nil
        defer {
            isSyncing = false
            progress = nil
        }

        do {
            lastSummary = try await syncer.sync { update in
                Task { @MainActor in self.progress = update }
            }
            isOffline = false
            lastSyncedAt = Date()
            UserDefaults.standard.set(lastSyncedAt, forKey: Self.lastSyncedKey)
        } catch is CancellationError {
            // The view went away; not a failure worth surfacing.
        } catch {
            let discogsError = error as? DiscogsError
            isOffline = discogsError?.isOffline ?? false
            // Offline is reported as a status line, not an error banner: the cache still works.
            errorMessage = isOffline ? nil : error.localizedDescription
        }
    }
}
