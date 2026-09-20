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
        .task(id: TaskKey(releaseID: releaseID, edge: bucketedEdge)) { await load() }
    }

    /// Rounding the requested size to a step stops a drag of the density slider from kicking off a
    /// fresh decode on every frame.
    private var bucketedEdge: CGFloat {
        (edge / 40).rounded(.up) * 40
    }

    private struct TaskKey: Hashable {
        let releaseID: Int
        let edge: CGFloat
    }

    private func load() async {
        guard let remoteURL, let url = URL(string: remoteURL) else {
            didFail = true
            return
        }
        do {
            let scale = PlatformScreenScale.value
            image = try await services.imageCache.image(
                releaseID: releaseID,
                kind: kind,
                remoteURL: url,
                maximumPixelSize: bucketedEdge * scale
            )
            didFail = false
        } catch is CancellationError {
            // A scrolled-away cell cancels its own load; nothing to report.
        } catch {
            didFail = true
        }
    }
}

enum PlatformScreenScale {
    @MainActor
    static var value: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.scale
        #else
        NSScreen.main?.backingScaleFactor ?? 2
        #endif
    }
}
