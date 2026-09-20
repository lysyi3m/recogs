import DiscogsKit
import Foundation
import SwiftData

/// A Discogs collection folder. v1's UI is flat, but the folders are cached so folder-awareness is
/// a fast follow rather than a new sync path.
@Model
final class CachedFolder {
    @Attribute(.unique) var id: Int
    var name: String
    var count: Int

    init(from folder: Folder) {
        id = folder.id
        name = folder.name
        count = folder.count
    }

    func update(from folder: Folder) {
        name = folder.name
        count = folder.count
    }
}
