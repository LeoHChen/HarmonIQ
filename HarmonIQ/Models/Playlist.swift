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
    /// True when this is the drive's system "Favorites" playlist. Each drive has
    /// at most one. Persisted to the drive (so all devices see the same set).
    var isFavorites: Bool
    /// True when this playlist was saved from an AI Smart Play queue. Persisted.
    var isSmart: Bool
    /// The user's original prompt (for Vibe Match), or nil for non-prompt
    /// modes / non-AI playlists. Persisted so the row can show what was typed.
    var smartPrompt: String?
    /// The `SmartPlayMode.rawValue` used to generate this queue, if any.
    /// Stored so a future "regenerate" action can rebuild it. Persisted.
    var smartMode: String?

    init(id: UUID = UUID(),
         name: String,
         trackIDs: [String] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         rootBookmarkID: UUID,
         isFavorites: Bool = false,
         isSmart: Bool = false,
         smartPrompt: String? = nil,
         smartMode: String? = nil) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rootBookmarkID = rootBookmarkID
        self.isFavorites = isFavorites
        self.isSmart = isSmart
        self.smartPrompt = smartPrompt
        self.smartMode = smartMode
    }
}

/// Cheap-check baseline used by the incremental indexer (issue #55). When
/// the drive root's mtime + immediate-child count match the stored
/// fingerprint, a Reindex is a near-instant no-op. Optional / Codable so
/// existing `roots.json` files migrate transparently.
struct ScanFingerprint: Codable, Hashable {
    var rootMtime: Date
    var childCount: Int
}

struct LibraryRoot: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var bookmark: Data
    var lastIndexed: Date?
    var trackCount: Int
    /// True when the picked folder doesn't grant write access (e.g. iOS system
    /// "Music" folder, certain iCloud locations). Index + playlists for a
    /// read-only root live in the app sandbox via SandboxRootStore instead of
    /// in the on-drive HarmonIQ/ folder.
    var isReadOnly: Bool
    /// Snapshot of the root's mtime + immediate-child count at the end of
    /// the last scan. Used by the cheap-check to skip walking when the
    /// drive's top-level layout is unchanged. nil → cheap check is
    /// skipped (next scan walks unconditionally and populates).
    var lastScanFingerprint: ScanFingerprint?

    init(id: UUID = UUID(),
         displayName: String,
         bookmark: Data,
         lastIndexed: Date? = nil,
         trackCount: Int = 0,
         isReadOnly: Bool = false,
         lastScanFingerprint: ScanFingerprint? = nil) {
        self.id = id
        self.displayName = displayName
        self.bookmark = bookmark
        self.lastIndexed = lastIndexed
        self.trackCount = trackCount
        self.isReadOnly = isReadOnly
        self.lastScanFingerprint = lastScanFingerprint
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, bookmark, lastIndexed, trackCount, isReadOnly, lastScanFingerprint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.bookmark = try c.decode(Data.self, forKey: .bookmark)
        self.lastIndexed = try c.decodeIfPresent(Date.self, forKey: .lastIndexed)
        self.trackCount = try c.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
        self.isReadOnly = try c.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false
        self.lastScanFingerprint = try c.decodeIfPresent(ScanFingerprint.self, forKey: .lastScanFingerprint)
    }
}
