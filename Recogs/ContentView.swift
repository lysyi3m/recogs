import DiscogsKit
import SwiftUI

/// Placeholder shell for step 1 of the build order. The collection grid lands in step 3; this view
/// exists so the app target links DiscogsKit and runs on both platforms.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "record.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Recogs")
                .font(.largeTitle.weight(.semibold))
            Text("DiscogsKit linked · \(DiscogsConfiguration.maximumPerPage) items per page")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
