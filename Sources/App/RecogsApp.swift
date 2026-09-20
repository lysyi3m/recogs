import RecogsKit
import SwiftUI

@main
struct RecogsApp: App {
    /// A cache that will not open is unrecoverable, so it is a first-class startup state rather
    /// than a crash.
    private enum Startup {
        case ready(AppServices)
        case failed(String)
    }

    @State private var startup: Startup

    init() {
        do {
            let container = try AppServices.makeModelContainer()
            _startup = State(initialValue: .ready(AppServices(modelContainer: container)))
        } catch {
            _startup = State(initialValue: .failed(error.localizedDescription))
        }
    }

    var body: some Scene {
        WindowGroup {
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
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
