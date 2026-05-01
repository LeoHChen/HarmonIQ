import Foundation

/// Per-root index storage in the app sandbox, used as a fallback for read-only
/// roots where DriveLibraryStore can't write a HarmonIQ/ folder onto the drive
/// (e.g. iOS system "Music" folder, iCloud locations the picker can't write to).
///
/// Layout:
///   Application Support/HarmonIQ/
///     RootIndexes/<rootID>.json    — DriveLibraryFile (tracks)
///     RootPlaylists/<rootID>.json  — DrivePlaylistsFile (playlists)
///
/// Reuses the DTOs from DriveLibraryStore so toggling a root between read-only
/// and read-write doesn't require reindexing.
enum SandboxRootStore {
    private static func appSupport() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("HarmonIQ", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func indexesDirectory() -> URL {
        let dir = appSupport().appendingPathComponent("RootIndexes", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func playlistsDirectory() -> URL {
        let dir = appSupport().appendingPathComponent("RootPlaylists", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func libraryFile(rootID: UUID) -> URL {
        indexesDirectory().appendingPathComponent("\(rootID.uuidString).json")
    }

    static func playlistsFile(rootID: UUID) -> URL {
        playlistsDirectory().appendingPathComponent("\(rootID.uuidString).json")
    }

    // MARK: - Library IO

    static func loadLibrary(rootID: UUID) -> DriveLibraryStore.DriveLibraryFile? {
        guard let data = try? Data(contentsOf: libraryFile(rootID: rootID)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DriveLibraryStore.DriveLibraryFile.self, from: data)
    }

    static func writeLibrary(_ file: DriveLibraryStore.DriveLibraryFile, rootID: UUID) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        try data.write(to: libraryFile(rootID: rootID), options: .atomic)
    }

    // MARK: - Playlists IO

    static func loadPlaylists(rootID: UUID) -> DriveLibraryStore.DrivePlaylistsFile? {
        guard let data = try? Data(contentsOf: playlistsFile(rootID: rootID)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DriveLibraryStore.DrivePlaylistsFile.self, from: data)
    }

    static func writePlaylists(_ file: DriveLibraryStore.DrivePlaylistsFile, rootID: UUID) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        try data.write(to: playlistsFile(rootID: rootID), options: .atomic)
    }

    /// Removes both the index and playlists for a root. Called when a root is
    /// removed so we don't leave orphan files behind.
    static func deleteAll(rootID: UUID) {
        try? FileManager.default.removeItem(at: libraryFile(rootID: rootID))
        try? FileManager.default.removeItem(at: playlistsFile(rootID: rootID))
    }
}
