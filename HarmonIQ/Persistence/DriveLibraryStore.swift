import Foundation

/// Reads and writes a drive's HarmonIQ folder — the on-drive source of truth for
/// indexed tracks, playlists, and cached artwork. Layout at the drive root:
///
///   HarmonIQ/
///     library.json
///     playlists.json
///     Artwork/<sha1>.jpg
///
/// Per-device fields (UUID bookmark IDs, file bookmarks) are NEVER written to the
/// drive — they're rebound to the current device when the file is loaded. This keeps
/// the same drive usable from any iPhone without reindexing.
enum DriveLibraryStore {
    static let folderName = "HarmonIQ"
    static let libraryFileName = "library.json"
    static let playlistsFileName = "playlists.json"
    static let artworkFolderName = "Artwork"

    // MARK: - DTOs

    struct DriveLibraryFile: Codable {
        var version: Int
        var tracks: [DriveTrack]
    }

    struct DriveTrack: Codable {
        var stableID: String
        var relativePath: [String]
        var filename: String
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
        /// File mtime at last scan. Optional so library.json files written
        /// by builds before issue #55 still decode; treated as "unknown,
        /// re-extract once" by the indexer to backfill on next scan.
        var fileModified: Date?
        /// Heuristic language bucket (issue #86). Optional so library.json
        /// files written before classification existed decode cleanly — a
        /// nil row is reclassified on the next index run, or via the
        /// Settings "Reclassify all tracks" action.
        var language: String?
    }

    struct DrivePlaylistsFile: Codable {
        var version: Int
        var playlists: [DrivePlaylist]
    }

    struct DrivePlaylist: Codable {
        var id: UUID
        var name: String
        var trackIDs: [String]
        var createdAt: Date
        var updatedAt: Date
        /// Optional kind tag.
        ///   `"favorites"` — the drive's system Favorites playlist.
        ///   `"smart"`     — saved from an AI Smart Play queue (issue #58).
        ///   nil / missing — a normal hand-built playlist.
        /// Optional so existing playlists.json files decode unchanged.
        var kind: String?
        /// Original user prompt for AI-curated playlists (issue #58). Optional.
        var smartPrompt: String?
        /// `SmartPlayMode.rawValue` used to generate this AI-curated queue. Optional.
        var smartMode: String?
    }

    // MARK: - Paths

    static func harmonIQFolder(in driveRoot: URL) -> URL {
        driveRoot.appendingPathComponent(folderName, isDirectory: true)
    }

    static func libraryFile(in driveRoot: URL) -> URL {
        harmonIQFolder(in: driveRoot).appendingPathComponent(libraryFileName)
    }

    static func playlistsFile(in driveRoot: URL) -> URL {
        harmonIQFolder(in: driveRoot).appendingPathComponent(playlistsFileName)
    }

    static func artworkFolder(in driveRoot: URL) -> URL {
        harmonIQFolder(in: driveRoot).appendingPathComponent(artworkFolderName, isDirectory: true)
    }

    /// Per-artist photo folder (issue #93). Sibling to `artworkFolder` —
    /// album covers stay at `<HarmonIQ>/Artwork/<sha1(albumArtist|album)>.jpg`,
    /// artist photos live one level deeper at
    /// `<HarmonIQ>/Artwork/artists/<sha1(artistName)>.jpg` so the album
    /// rescan sweep ignores them.
    static let artistArtworkFolderName = "artists"

    static func artistArtworkFolder(in driveRoot: URL) -> URL {
        artworkFolder(in: driveRoot).appendingPathComponent(artistArtworkFolderName, isDirectory: true)
    }

    static func ensureFolders(in driveRoot: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: harmonIQFolder(in: driveRoot), withIntermediateDirectories: true)
        try fm.createDirectory(at: artworkFolder(in: driveRoot), withIntermediateDirectories: true)
    }

    // MARK: - Library IO

    static func loadLibrary(driveRoot: URL) -> DriveLibraryFile? {
        let url = libraryFile(in: driveRoot)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DriveLibraryFile.self, from: data)
    }

    static func writeLibrary(_ file: DriveLibraryFile, driveRoot: URL) throws {
        try ensureFolders(in: driveRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        try data.write(to: libraryFile(in: driveRoot), options: .atomic)
    }

    // MARK: - Playlists IO

    static func loadPlaylists(driveRoot: URL) -> DrivePlaylistsFile? {
        let url = playlistsFile(in: driveRoot)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DrivePlaylistsFile.self, from: data)
    }

    static func writePlaylists(_ file: DrivePlaylistsFile, driveRoot: URL) throws {
        try ensureFolders(in: driveRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        try data.write(to: playlistsFile(in: driveRoot), options: .atomic)
    }

    // MARK: - Mapping

    static func toTrack(_ dt: DriveTrack, rootBookmarkID: UUID) -> Track {
        Track(
            id: UUID(),
            stableID: dt.stableID,
            relativePath: dt.relativePath,
            filename: dt.filename,
            rootBookmarkID: rootBookmarkID,
            fileBookmark: nil,
            title: dt.title,
            artist: dt.artist,
            album: dt.album,
            albumArtist: dt.albumArtist,
            genre: dt.genre,
            year: dt.year,
            trackNumber: dt.trackNumber,
            discNumber: dt.discNumber,
            duration: dt.duration,
            fileSize: dt.fileSize,
            fileFormat: dt.fileFormat,
            artworkPath: dt.artworkPath,
            fileModified: dt.fileModified,
            language: dt.language.flatMap { TrackLanguage(rawValue: $0) }
        )
    }

    static func fromTrack(_ t: Track) -> DriveTrack {
        DriveTrack(
            stableID: t.stableID,
            relativePath: t.relativePath,
            filename: t.filename,
            title: t.title,
            artist: t.artist,
            album: t.album,
            albumArtist: t.albumArtist,
            genre: t.genre,
            year: t.year,
            trackNumber: t.trackNumber,
            discNumber: t.discNumber,
            duration: t.duration,
            fileSize: t.fileSize,
            fileFormat: t.fileFormat,
            artworkPath: t.artworkPath,
            fileModified: t.fileModified,
            language: t.language?.rawValue
        )
    }

    static let favoritesKind = "favorites"
    static let smartKind = "smart"

    static func toPlaylist(_ dp: DrivePlaylist, rootBookmarkID: UUID) -> Playlist {
        Playlist(
            id: dp.id,
            name: dp.name,
            trackIDs: dp.trackIDs,
            createdAt: dp.createdAt,
            updatedAt: dp.updatedAt,
            rootBookmarkID: rootBookmarkID,
            isFavorites: dp.kind == favoritesKind,
            isSmart: dp.kind == smartKind,
            smartPrompt: dp.smartPrompt,
            smartMode: dp.smartMode
        )
    }

    static func fromPlaylist(_ p: Playlist) -> DrivePlaylist {
        let kind: String?
        if p.isFavorites { kind = favoritesKind }
        else if p.isSmart { kind = smartKind }
        else { kind = nil }
        return DrivePlaylist(
            id: p.id,
            name: p.name,
            trackIDs: p.trackIDs,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt,
            kind: kind,
            smartPrompt: p.isSmart ? p.smartPrompt : nil,
            smartMode: p.isSmart ? p.smartMode : nil
        )
    }

    // MARK: - Artwork mirroring

    /// Copies the drive's Artwork folder contents into the local cache so views and
    /// MPNowPlayingInfo can read art without holding a security-scoped resource open.
    /// Skips files that already exist locally with the same byte count.
    static func mirrorArtworkToLocalCache(driveRoot: URL, localCache: URL) {
        let driveArt = artworkFolder(in: driveRoot)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: driveArt, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return }
        if !fm.fileExists(atPath: localCache.path) {
            try? fm.createDirectory(at: localCache, withIntermediateDirectories: true)
        }
        for src in entries {
            // Skip subdirectories — `artists/` has its own mirror pass.
            let isDir = (try? src.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }
            let dst = localCache.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dst.path) {
                let s = (try? src.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                let d = (try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
                if s == d { continue }
                try? fm.removeItem(at: dst)
            }
            try? fm.copyItem(at: src, to: dst)
        }
    }

    /// Mirrors the drive's per-artist photo folder into the local cache
    /// (issue #93). Same byte-size shortcut as the album mirror so we don't
    /// re-copy files that haven't changed across launches.
    static func mirrorArtistPhotosToLocalCache(driveRoot: URL, localCache: URL) {
        let driveArt = artistArtworkFolder(in: driveRoot)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: driveArt, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return }
        if !fm.fileExists(atPath: localCache.path) {
            try? fm.createDirectory(at: localCache, withIntermediateDirectories: true)
        }
        for src in entries {
            let isDir = (try? src.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }
            let dst = localCache.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dst.path) {
                let s = (try? src.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                let d = (try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
                if s == d { continue }
                try? fm.removeItem(at: dst)
            }
            try? fm.copyItem(at: src, to: dst)
        }
    }
}
