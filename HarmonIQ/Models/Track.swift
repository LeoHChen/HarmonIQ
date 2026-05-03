import Foundation

struct Track: Identifiable, Codable, Hashable {
    let id: UUID
    /// Stable identity derived from the on-drive path so re-indexing keeps the same id.
    let stableID: String
    /// Path components relative to the indexed root, e.g. ["Pink Floyd", "The Wall", "01 - In the Flesh.mp3"].
    var relativePath: [String]
    /// Filename only.
    var filename: String
    /// Bookmark identifier this track belongs to (the security-scoped root the user picked).
    var rootBookmarkID: UUID
    /// Stored bookmark for the file itself when available, otherwise empty.
    var fileBookmark: Data?

    var title: String
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var discNumber: Int?
    var duration: TimeInterval
    var fileSize: Int64
    var fileFormat: String
    var artworkPath: String?
    /// File's last-modified date at the time of the most recent scan.
    /// `nil` means the field hasn't been backfilled yet (i.e. the row was
    /// indexed by a build before issue #55). The next reindex treats nil
    /// as "unknown — re-extract once" so the field gets populated.
    var fileModified: Date?
    /// Heuristic language bucket (issue #86). Computed at index time from
    /// `title + artist`. Optional so library.json files written before
    /// language classification existed decode cleanly — those rows get
    /// classified on the next index run, or via the Settings →
    /// "Reclassify all tracks" action.
    var language: TrackLanguage?

    var displayTitle: String { title.isEmpty ? filename : title }
    var displayArtist: String { (artist?.nilIfBlank) ?? (albumArtist?.nilIfBlank) ?? "Unknown Artist" }
    var displayAlbum: String { (album?.nilIfBlank) ?? "Unknown Album" }

    /// Effective language bucket. Falls back to `.others` for rows that
    /// haven't been classified yet (legacy library.json files written
    /// before issue #86). Use this in views; the optional `language`
    /// field is only for persistence.
    var effectiveLanguage: TrackLanguage {
        language ?? TrackLanguage.classify(title: title, artist: artist)
    }

    var folderPath: [String] { Array(relativePath.dropLast()) }
    var folderKey: String { folderPath.joined(separator: "/") }

    static func == (lhs: Track, rhs: Track) -> Bool { lhs.stableID == rhs.stableID }
    func hash(into hasher: inout Hasher) { hasher.combine(stableID) }
}

extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

extension String {
    var nilIfBlank: String? {
        let s = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
