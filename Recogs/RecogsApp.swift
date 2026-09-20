import SwiftUI

@main
struct RecogsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
