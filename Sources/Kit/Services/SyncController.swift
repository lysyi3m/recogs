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

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
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
        } catch is CancellationError {
            // The view went away; not a failure worth surfacing.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
