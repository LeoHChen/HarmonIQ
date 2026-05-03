#!/usr/bin/env swift
//
// library-doctor.swift — offline maintenance for HarmonIQ's on-drive library.json.
//
// Usage (see tools/README.md for the long version):
//
//   swift tools/library-doctor.swift --report  /Volumes/Music
//   swift tools/library-doctor.swift --dedupe  /Volumes/Music
//   swift tools/library-doctor.swift --rebuild /Volumes/Music
//
// The drive path is the folder you picked in HarmonIQ (the parent of
// `HarmonIQ/library.json`), not the `HarmonIQ/` folder itself.
//
// This script is self-contained: it duplicates the on-disk JSON shape so
// HarmonIQ.app doesn't need to be linked. If `DriveLibraryStore.DriveTrack`
// gains required fields, mirror them here too.
//
// Issue #88.

import Foundation

// MARK: - On-disk shape (mirrors DriveLibraryStore.DriveTrack / DriveLibraryFile)

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
    var duration: Double
    var fileSize: Int64
    var fileFormat: String
    var artworkPath: String?
    var fileModified: Date?
    /// Issue #86 field — optional in v1, populated by the indexer.
    var language: String?
}

struct DriveLibraryFile: Codable {
    var version: Int
    var tracks: [DriveTrack]
}

// MARK: - CLI

enum Mode: String {
    case report = "--report"
    case dedupe = "--dedupe"
    case rebuild = "--rebuild"
}

func usage() -> Never {
    let msg = """
    library-doctor — HarmonIQ library.json maintenance

    USAGE:
      swift tools/library-doctor.swift --report  <drive-root>
      swift tools/library-doctor.swift --dedupe  <drive-root>
      swift tools/library-doctor.swift --rebuild <drive-root>

    MODES:
      --report   Print compilation albums and duplicate stableID counts. Read-only.
      --dedupe   Collapse rows that share a stableID (keeps the first). Writes back.
      --rebuild  Delete library.json so the next app launch reindexes from scratch.
                 Playlists survive — they reference tracks by stableID
                 (sha1(relativePath)), which a clean reindex regenerates.

    <drive-root> is the folder you picked in HarmonIQ — the PARENT of HarmonIQ/.
    """
    FileHandle.standardError.write(Data(msg.utf8) + Data("\n".utf8))
    exit(64)
}

let args = CommandLine.arguments
guard args.count == 3, let mode = Mode(rawValue: args[1]) else { usage() }
let driveRoot = URL(fileURLWithPath: args[2], isDirectory: true)
let libraryURL = driveRoot
    .appendingPathComponent("HarmonIQ", isDirectory: true)
    .appendingPathComponent("library.json")

// MARK: - IO helpers

let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return e
}()

func readLibrary() -> DriveLibraryFile {
    do {
        let data = try Data(contentsOf: libraryURL)
        return try decoder.decode(DriveLibraryFile.self, from: data)
    } catch {
        FileHandle.standardError.write(Data("error: couldn't read \(libraryURL.path): \(error)\n".utf8))
        exit(2)
    }
}

func writeLibraryAtomically(_ file: DriveLibraryFile) {
    do {
        let data = try encoder.encode(file)
        try data.write(to: libraryURL, options: .atomic)
    } catch {
        FileHandle.standardError.write(Data("error: couldn't write \(libraryURL.path): \(error)\n".utf8))
        exit(3)
    }
}

// MARK: - Modes

func runReport() {
    let lib = readLibrary()
    print("library.json: \(libraryURL.path)")
    print("version: \(lib.version)  tracks: \(lib.tracks.count)")
    print("")

    // Duplicate stableID rows.
    var counts: [String: Int] = [:]
    for t in lib.tracks { counts[t.stableID, default: 0] += 1 }
    let dupes = counts.filter { $0.value > 1 }
    if dupes.isEmpty {
        print("stableID uniqueness: OK")
    } else {
        let total = dupes.values.reduce(0, +) - dupes.count
        print("stableID uniqueness: FAIL — \(dupes.count) ids account for \(total) extra rows")
        let sample = dupes.sorted { $0.value > $1.value }.prefix(5)
        for (sid, n) in sample {
            print("  \(sid)  ×\(n)")
        }
    }
    print("")

    // Compilation candidates: same album with ≥3 distinct artists.
    var byAlbum: [String: Set<String>] = [:]
    for t in lib.tracks {
        let album = (t.album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !album.isEmpty else { continue }
        let artist = (t.artist ?? t.albumArtist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artist.isEmpty else { continue }
        byAlbum[album, default: []].insert(artist)
    }
    let comps = byAlbum.filter { $0.value.count >= 3 }
        .sorted { $0.value.count > $1.value.count }
    if comps.isEmpty {
        print("compilations: none detected (≥3 distinct artists per album threshold)")
    } else {
        print("compilations: \(comps.count) album(s) look like compilations:")
        for (album, artists) in comps.prefix(20) {
            print("  \(album)  (\(artists.count) distinct artists)")
        }
        if comps.count > 20 { print("  … and \(comps.count - 20) more") }
    }
}

func runDedupe() {
    let lib = readLibrary()
    var seen: Set<String> = []
    var deduped: [DriveTrack] = []
    deduped.reserveCapacity(lib.tracks.count)
    for t in lib.tracks {
        if seen.insert(t.stableID).inserted {
            deduped.append(t)
        }
    }
    let removed = lib.tracks.count - deduped.count
    if removed == 0 {
        print("dedupe: nothing to do — already unique on stableID (\(lib.tracks.count) tracks).")
        return
    }
    var out = lib
    out.tracks = deduped
    writeLibraryAtomically(out)
    print("dedupe: collapsed \(removed) duplicate row(s); \(deduped.count) unique tracks remain.")
}

func runRebuild() {
    if FileManager.default.fileExists(atPath: libraryURL.path) {
        do {
            try FileManager.default.removeItem(at: libraryURL)
            print("rebuild: deleted \(libraryURL.path).")
        } catch {
            FileHandle.standardError.write(Data("error: couldn't delete \(libraryURL.path): \(error)\n".utf8))
            exit(4)
        }
    } else {
        print("rebuild: \(libraryURL.path) wasn't there — nothing to delete.")
    }
    print("rebuild: launch HarmonIQ on a device with this drive mounted to reindex from scratch.")
    print("rebuild: playlists at HarmonIQ/playlists.json were left alone.")
}

switch mode {
case .report:  runReport()
case .dedupe:  runDedupe()
case .rebuild: runRebuild()
}
