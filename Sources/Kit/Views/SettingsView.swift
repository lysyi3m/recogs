import DiscogsKit
import SwiftUI

/// App settings. Two concerns: what is cached, and which account it came from.
///
/// macOS presents these as tabs in the Settings window; iOS as sections in a sheet.
public struct SettingsView: View {
    /// Called after signing out, so the presenter can close itself.
    var onSignedOut: () -> Void

    public init(onSignedOut: @escaping () -> Void = {}) {
        self.onSignedOut = onSignedOut
    }

    public var body: some View {
        #if os(macOS)
        TabView {
            CollectionSettingsView()
                .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
            AccountSettingsView(onSignedOut: onSignedOut)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        // Tall enough for the Collection tab, which is the longer of the two; a short window
        // hides its first section behind the tab bar.
        .frame(width: 520, height: 420)
        #else
        NavigationStack {
            Form {
                CollectionSettingsView()
                AccountSettingsView(onSignedOut: onSignedOut)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        #endif
    }
}

// MARK: - Collection

/// Cache state and the two manual controls worth having when something looks wrong.
struct CollectionSettingsView: View {
    @Environment(AppServices.self) private var services

    @State private var summary: CacheSummary?
    @State private var isConfirmingReset = false
    @State private var message: String?

    private var syncController: SyncController { services.syncController }

    private struct CacheSummary: Equatable {
        var items: Int
        var folders: Int
        var images: ImageCache.Statistics
    }

    private var isWorking: Bool { syncController.isSyncing }

    var body: some View {
        content
            .task { await refreshSummary() }
            .confirmationDialog(
                "Reset the cache?",
                isPresented: $isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button("Reset Cache", role: .destructive) {
                    Task { await resetAndResync() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears the collection and covers stored on this device, then downloads them again. Nothing in your Discogs collection changes.")
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        Form {
            sections
        }
        .formStyle(.grouped)
        #else
        sections
        #endif
    }

    @ViewBuilder
    private var sections: some View {
        Section("Sync") {
            LabeledContent("Last synced", value: lastSyncedText)
            if let summary {
                LabeledContent("Records", value: "\(summary.items)")
                LabeledContent("Folders", value: "\(summary.folders)")
            }
        }

        Section("Cover art") {
            if let summary {
                LabeledContent("Images on disk", value: "\(summary.images.fileCount)")
                LabeledContent(
                    "Size",
                    value: summary.images.byteCount.formatted(.byteCount(style: .file))
                )
            }
        }

        Section {
            // Both actions on one row, with their own progress beside them: a disabled button is
            // not a progress indicator.
            HStack(spacing: 10) {
                Button("Sync Now") { Task { await syncNow() } }
                    .disabled(isWorking || !services.hasToken)
                Button("Reset Cache", role: .destructive) { isConfirmingReset = true }
                    .disabled(isWorking || !services.hasToken)

                Spacer(minLength: 8)

                if let activity = syncController.activity {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(activity)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(message)
                }
            }
        }
    }

    private var lastSyncedText: String {
        guard let lastSyncedAt = syncController.lastSyncedAt else { return "Never" }
        return lastSyncedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func syncNow() async {
        message = nil
        await syncController.sync()
        // `sync` clears the error when the cause is simply being offline, so that case has to be
        // reported here rather than passed off as success.
        if let errorMessage = syncController.errorMessage {
            message = errorMessage
        } else if syncController.isOffline {
            message = "Offline — nothing synced"
        } else {
            message = "Sync finished"
        }
        await refreshSummary()
    }

    private func resetAndResync() async {
        message = nil
        do {
            try await syncController.resetAndResync()
            message = syncController.errorMessage ?? "Cache rebuilt"
        } catch {
            message = error.localizedDescription
        }
        await refreshSummary()
    }

    private func refreshSummary() async {
        summary = CacheSummary(
            items: (try? await services.store.itemCount()) ?? 0,
            folders: (try? await services.store.folders().count) ?? 0,
            images: await services.imageCache.statistics()
        )
    }
}

// MARK: - Account

struct AccountSettingsView: View {
    var onSignedOut: () -> Void

    @Environment(AppServices.self) private var services

    @State private var isConfirmingSignOut = false
    @State private var errorMessage: String?

    var body: some View {
        content
            .confirmationDialog(
                "Disconnect this account?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) { Task { await signOut() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the token from this device and clears the cached collection. Nothing in your Discogs collection changes.")
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        Form { sections }.formStyle(.grouped)
        #else
        sections
        #endif
    }

    @ViewBuilder
    private var sections: some View {
        Section("Discogs account") {
            LabeledContent("Username", value: services.accountUsername ?? "Unknown")
            LabeledContent("Token") {
                Text(services.maskedToken ?? "None")
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            Button("Disconnect Account", role: .destructive) { isConfirmingSignOut = true }
                .disabled(!services.hasToken)
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text("The token is stored in the Keychain on this device only, and is never logged.")
        }
    }

    private func signOut() async {
        do {
            try await services.signOut()
            onSignedOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
