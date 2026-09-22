import SwiftUI

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Cover art loaded from the disk cache, downsampled to the size it is drawn at.
///
/// Decoding at display size is what keeps a wall of covers memory-bounded: a full-res cover is
/// several megabytes decoded, and the grid may show hundreds at once.
struct CoverImageView: View {
    let releaseID: Int
    let remoteURL: String?
    let kind: ImageCache.Kind
    /// Drawn edge length in points. The image is decoded at this size times the screen scale.
    let edge: CGFloat

    @Environment(AppServices.self) private var services
    /// The scale of the display actually showing this view. `UIScreen.main` assumed one screen and
    /// is deprecated; this follows the window the cover is drawn in.
    @Environment(\.displayScale) private var displayScale
    @State private var image: PlatformImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: didFail ? "exclamationmark.triangle" : "opticaldisc")
                            .font(.system(size: max(edge * 0.25, 10)))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        // The URL is part of the identity: a record detail starts with the collection's cover and
        // switches to the release's own once that arrives, and the load has to follow it.
        .task(id: TaskKey(releaseID: releaseID, kind: kind, url: remoteURL, edge: bucketedEdge)) {
            await load()
        }
    }

    /// Rounding the requested size to a step stops a drag of the density slider from kicking off a
    /// fresh decode on every frame.
    private var bucketedEdge: CGFloat {
        (edge / 40).rounded(.up) * 40
    }

    private struct TaskKey: Hashable {
        let releaseID: Int
        let kind: ImageCache.Kind
        let url: String?
        let edge: CGFloat
    }

    private func load() async {
        guard let remoteURL, let url = URL(string: remoteURL) else {
            didFail = true
            return
        }
        do {
            image = try await services.imageCache.image(
                releaseID: releaseID,
                kind: kind,
                remoteURL: url,
                maximumPixelSize: bucketedEdge * displayScale
            )
            didFail = false
        } catch is CancellationError {
            // A scrolled-away cell cancels its own load; nothing to report.
        } catch {
            didFail = true
        }
    }
}
