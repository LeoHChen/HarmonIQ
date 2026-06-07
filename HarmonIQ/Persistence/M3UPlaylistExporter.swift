import Foundation

/// Exports HarmonIQ playlists as standard `.m3u8` files onto the drive so they can
/// be opened in VLC — or any desktop player — when the drive is mounted on a Mac/PC.
///
/// HarmonIQ's own `playlists.json` is keyed by `Track.stableID` (a path hash) and is
/// not understood by other players. This sidecar writes the same playlists in the
/// universally-recognised Extended M3U format. Layout on the drive:
///
///   <DriveRoot>/HarmonIQ/Playlists/<name>.m3u8
///
/// Entry paths are written **relative to that folder** (`../../<relativePath>`), so
/// they resolve regardless of where the OS mounts the drive (`/Volumes/MyHD` on a
/// Mac, a drive letter on Windows, the security-scoped URL on iOS). `.m3u8` (UTF-8)
/// is used rather than `.m3u` so non-ASCII artist/track paths survive intact.
///
/// The whole folder is regenerated on every write: the `.m3u8` files we manage are
/// cleared first, so renamed or deleted playlists never leave orphans behind.
enum M3UPlaylistExporter {
    static let playlistsFolderName = "Playlists"

    static func playlistsFolder(in driveRoot: URL) -> URL {
        DriveLibraryStore.harmonIQFolder(in: driveRoot)
            .appendingPathComponent(playlistsFolderName, isDirectory: true)
    }

    /// Regenerates the `Playlists/` folder from `playlists`. Each entry pairs a
    /// playlist name with its tracks already resolved **in playlist order** — the
    /// caller drops track IDs that don't resolve (e.g. an offline drive), so a line
    /// is only emitted for a track whose on-drive path is known.
    static func export(_ playlists: [(name: String, tracks: [Track])], driveRoot: URL) throws {
        let fm = FileManager.default
        let folder = playlistsFolder(in: driveRoot)

        // Wipe the .m3u8 files we manage so renames/deletes don't leave orphans.
        // Anything else the user dropped in the folder is left untouched.
        if let existing = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for url in existing where url.pathExtension.lowercased() == "m3u8" {
                try? fm.removeItem(at: url)
            }
        }

        guard !playlists.isEmpty else { return }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // De-collide filenames: two playlists may share a (sanitised) name.
        var usedNames = Set<String>()
        for playlist in playlists {
            let base = sanitizedFilename(playlist.name)
            var name = base
            var suffix = 2
            while !usedNames.insert(name.lowercased()).inserted {
                name = "\(base) (\(suffix))"
                suffix += 1
            }
            let url = folder.appendingPathComponent(name).appendingPathExtension("m3u8")
            let data = Data(m3u8Content(for: playlist.tracks).utf8)
            try data.write(to: url, options: .atomic)
        }
    }

    /// Builds Extended M3U text for an ordered track list. Relative entries point
    /// up two levels — out of `HarmonIQ/Playlists/` to the drive root — then down
    /// each track's `relativePath`.
    static func m3u8Content(for tracks: [Track]) -> String {
        var lines = ["#EXTM3U"]
        for track in tracks {
            let seconds = Int(track.duration.rounded())
            lines.append("#EXTINF:\(seconds),\(track.displayArtist) - \(track.displayTitle)")
            lines.append((["..", ".."] + track.relativePath).joined(separator: "/"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Strips characters that are illegal in filenames on common filesystems
    /// (FAT/exFAT/HFS+/APFS/NTFS) so the export works on whatever the drive is
    /// formatted as. Falls back to "Playlist" if nothing usable remains.
    static func sanitizedFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .reduce(into: "") { result, scalar in
                result.unicodeScalars.append(illegal.contains(scalar) ? "_" : scalar)
            }
        return cleaned.isEmpty ? "Playlist" : cleaned
    }
}
