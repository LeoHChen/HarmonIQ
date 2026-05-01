import Foundation

struct Playlist: Identifiable, Hashable {
    let id: UUID
    var name: String
    var trackIDs: [String]
    var createdAt: Date
    var updatedAt: Date
    /// Which drive owns this playlist. In-memory only — bound when the playlist
    /// is loaded from the drive (or when it is created), never serialized to disk.
    var rootBookmarkID: UUID

    init(id: UUID = UUID(),
         name: String,
         trackIDs: [String] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         rootBookmarkID: UUID) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rootBookmarkID = rootBookmarkID
    }
}

struct LibraryRoot: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var bookmark: Data
    var lastIndexed: Date?
    var trackCount: Int

    init(id: UUID = UUID(), displayName: String, bookmark: Data, lastIndexed: Date? = nil, trackCount: Int = 0) {
        self.id = id
        self.displayName = displayName
        self.bookmark = bookmark
        self.lastIndexed = lastIndexed
        self.trackCount = trackCount
    }
}
