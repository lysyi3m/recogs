import DiscogsKit
import Foundation
import SwiftData

/// A Discogs collection folder. The UI shows one flat collection. Folders are cached so a folder
/// view needs no new sync path.
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
