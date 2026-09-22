import RecogsKit
import SwiftUI

#if os(macOS)
import AppKit

/// Trims menu items SwiftUI adds that this app has no use for.
///
/// A single `Window` scene still contributes File ▸ New Window, which here only re-focuses the
/// window that is already open. No command group replaces it, so it is removed from the menu
/// directly, along with the separator it leaves behind.
final class MenuTrimmingAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep AppKit's runtime icon in sync with the compiled asset catalog. During development,
        // Launch Services can otherwise retain the placeholder from an older build at this path.
        // NSWorkspace applies the system icon shape, but reports a 32 pt logical size; correcting
        // that size lets Dock use its high-resolution representations instead of scaling one up.
        if let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath).copy() as? NSImage {
            appIcon.size = NSSize(width: 512, height: 512)
            NSApp.applicationIconImage = appIcon
        }

        guard let fileMenu = NSApp.mainMenu?.items
            .compactMap(\.submenu)
            .first(where: { menu in
                menu.items.contains { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command }
            })
        else { return }

        // Matched on the shortcut rather than the title, which is localized.
        for item in fileMenu.items where item.keyEquivalent == "n" && item.keyEquivalentModifierMask == .command {
            fileMenu.removeItem(item)
        }
        while fileMenu.items.first?.isSeparatorItem == true {
            fileMenu.removeItem(at: 0)
        }
    }
}
#endif

@main
struct RecogsApp: App {
    /// A cache that will not open is unrecoverable, so it is a first-class startup state rather
    /// than a crash.
    private enum Startup {
        case ready(AppServices)
        case failed(String)
    }

    @State private var startup: Startup

    #if os(macOS)
    @NSApplicationDelegateAdaptor(MenuTrimmingAppDelegate.self) private var appDelegate
    #endif

    init() {
        do {
            let container = try AppServices.makeModelContainer()
            _startup = State(initialValue: .ready(AppServices(modelContainer: container)))
        } catch {
            _startup = State(initialValue: .failed(error.localizedDescription))
        }
    }

    var body: some Scene {
        #if os(macOS)
        // One collection, one window. `Window` also drops File ▸ New Window and the window tab
        // bar that `WindowGroup` brings with it, neither of which means anything here.
        Window("Recogs", id: "collection") {
            rootView
                // Below this the status bar runs out of room and the record count collides with
                // the sync state: the density control, the centred count and the status need
                // roughly 500pt between them before anything overlaps.
                .frame(minWidth: 560, minHeight: 420)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            // ⌘, is wired by the Settings scene below. With a single `Window` scene the New Window
            // item only re-focuses the window that is already open, so ⌘N is free for adding a
            // record — the conventional meaning of New.
            CommandGroup(replacing: .newItem) {
                if case .ready(let services) = startup {
                    Button("Add Record…") { services.commands.requestAdd() }
                        .keyboardShortcut("n", modifiers: .command)
                }
            }
            CommandGroup(replacing: .singleWindowList) {}

            CommandMenu("Collection") {
                if case .ready(let services) = startup {
                    Button("Sync Now") { services.commands.requestSync() }
                        .keyboardShortcut("r", modifiers: .command)
                    Divider()
                    Button("Find in Collection") { services.commands.requestFind() }
                        .keyboardShortcut("f", modifiers: .command)
                }
            }
        }
        Settings {
            if case .ready(let services) = startup {
                SettingsView {
                    // Signing out returns the app to onboarding; the Settings window has nothing
                    // left to show.
                    NSApp.keyWindow?.close()
                }
                .environment(services)
                .modelContainer(services.modelContainer)
            }
        }
        #else
        WindowGroup {
            rootView
        }
        #endif
    }

    @ViewBuilder
    private var rootView: some View {
        switch startup {
        case .ready(let services):
            ContentView()
                .environment(services)
                .modelContainer(services.modelContainer)
        case .failed(let message):
            ContentUnavailableView(
                "Cache Unavailable",
                systemImage: "externaldrive.badge.xmark",
                description: Text(message)
            )
        }
    }
}
