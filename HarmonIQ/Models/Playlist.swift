import Foundation

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var trackIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, trackIDs: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
