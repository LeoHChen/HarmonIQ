import Foundation
import Combine
import CryptoKit
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var roots: [LibraryRoot] = []
    @Published private(set) var playlists: [Playlist] = []

    /// Status from the most recent artwork rescan (for the Settings footer).
    @Published private(set) var artworkRescanStatus: String = ""

    private let queue = DispatchQueue(label: "net.leochen.harmoniq.librarystore", qos: .utility)

    // MARK: - Local-only persistence (device-specific bookmarks)

    private var rootsFileURL: URL {
        appSupportDirectory().appendingPathComponent("roots.json")
    }

    private func appSupportDirectory() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("HarmonIQ", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Local mirror of artwork so views and MPNowPlayingInfo can load images without
    /// holding security-scoped access on the drive. Drive remains the source of truth;
    /// this directory is rebuilt from the drive on load.
    var artworkDirectory: URL {
        let dir = appSupportDirectory().appendingPathComponent("Artwork", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Load / save

    func loadFromDisk() async {
        let url = rootsFileURL
        let loadedRoots: [LibraryRoot] = await withCheckedContinuation { cont in
            queue.async {
                let decoder = JSONDecoder()
                if let data = try? Data(contentsOf: url),
                   let roots = try? decoder.decode([LibraryRoot].self, from: data) {
                    cont.resume(returning: roots)
                } else {
                    cont.resume(returning: [])
                }
            }
        }
        self.roots = loadedRoots

        // For each root, load its on-drive library + playlists.
        for root in loadedRoots {
            loadDriveData(for: root)
        }
    }

    private func saveRoots() {
        let snapshot = roots
        let url = rootsFileURL
        queue.async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Drive IO

    /// Resolves a root's bookmark, opens scope, and runs `body` with the URL. Stale
    /// bookmarks are refreshed and persisted before returning.
    @discardableResult
    private func withDriveAccess<T>(_ root: LibraryRoot, _ body: (URL) throws -> T) -> T? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: root.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            print("[HarmonIQ] Drive offline or bookmark resolve failed: \(root.displayName)")
            return nil
        }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        if stale, let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            if let idx = roots.firstIndex(where: { $0.id == root.id }) {
                roots[idx].bookmark = refreshed
                saveRoots()
            }
        }

        do {
            return try body(url)
        } catch {
            print("[HarmonIQ] Drive IO failed for \(root.displayName): \(error)")
            return nil
        }
    }

    /// Loads tracks + playlists for a root into in-memory state. Read-write roots
    /// pull from the on-drive HarmonIQ/ folder; read-only roots pull from the
    /// per-root sandbox shadow store (SandboxRootStore).
    private func loadDriveData(for root: LibraryRoot) {
        if root.isReadOnly {
            // Drive can't be written, so the index lives in the app sandbox.
            // We still open scope on the drive to mirror artwork (it's sometimes
            // readable even when the picker location is write-restricted).
            if let lib = SandboxRootStore.loadLibrary(rootID: root.id) {
                let mapped = lib.tracks.map { DriveLibraryStore.toTrack($0, rootBookmarkID: root.id) }
                mergeTracks(forRoot: root.id, with: mapped)
            }
            if let pls = SandboxRootStore.loadPlaylists(rootID: root.id) {
                let mapped = pls.playlists.map { DriveLibraryStore.toPlaylist($0, rootBookmarkID: root.id) }
                mergePlaylists(forRoot: root.id, with: mapped)
            }
            return
        }

        let cacheDir = artworkDirectory
        struct DriveLoad {
            var library: DriveLibraryStore.DriveLibraryFile?
            var playlists: DriveLibraryStore.DrivePlaylistsFile?
            var currentFingerprint: ScanFingerprint?
        }
        let result = withDriveAccess(root) { driveURL -> DriveLoad in
            let lib = DriveLibraryStore.loadLibrary(driveRoot: driveURL)
            let pls = DriveLibraryStore.loadPlaylists(driveRoot: driveURL)
            DriveLibraryStore.mirrorArtworkToLocalCache(driveRoot: driveURL, localCache: cacheDir)
            return DriveLoad(library: lib, playlists: pls, currentFingerprint: Self.computeFingerprint(rootURL: driveURL))
        }
        guard let result = result else { return }

        if let lib = result.library {
            let mapped = lib.tracks.map { DriveLibraryStore.toTrack($0, rootBookmarkID: root.id) }
            mergeTracks(forRoot: root.id, with: mapped)
        }
        if let pls = result.playlists {
            let mapped = pls.playlists.map { DriveLibraryStore.toPlaylist($0, rootBookmarkID: root.id) }
            mergePlaylists(forRoot: root.id, with: mapped)
        }

        // Adopt any artwork files that landed on disk between launches but
        // aren't referenced in library.json yet (issue #77). This is a
        // cheap pass: scan the Artwork folder, match by sha1 filename,
        // patch matching tracks. No-op when everything's already linked.
        reconcileArtworkOnLoad(rootID: root.id)

        // Auto-incremental: if the drive's top-level mtime + child count
        // differ from the last scan, kick off the indexer so newly-added
        // files appear without the user having to tap Reindex (issue
        // #58 / #55 follow-up). The indexer's own cheap-check will
        // bail near-instantly when nothing changed.
        if let current = result.currentFingerprint,
           current != root.lastScanFingerprint,
           !MusicIndexer.shared.isIndexing {
            MusicIndexer.shared.index(root: root)
        }
    }

    /// Cheap fingerprint helper. Mirrors `MusicIndexer.computeFingerprint` so
    /// the load path can decide whether to auto-trigger a scan without
    /// duplicating the file-walking step.
    private static func computeFingerprint(rootURL: URL) -> ScanFingerprint? {
        let fm = FileManager.default
        let rootValues = try? rootURL.resourceValues(forKeys: [.contentModificationDateKey])
        guard let mtime = rootValues?.contentModificationDate else { return nil }
        let children = (try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let count = children.filter { $0.lastPathComponent != DriveLibraryStore.folderName }.count
        return ScanFingerprint(rootMtime: mtime, childCount: count)
    }

    /// Re-reads a single drive's on-disk index without forcing a full
    /// reindex. Picks up tracks that landed via another device while
    /// this iPhone wasn't looking, and is what the Reload button in
    /// Settings calls.
    func reloadDrive(_ root: LibraryRoot) {
        loadDriveData(for: root)
    }

    /// Re-loads any drive that currently has zero in-memory tracks. Called
    /// when the app returns to the foreground — covers the common case of
    /// the user plugging a drive in while HarmonIQ was backgrounded. The
    /// per-drive cheap-check inside `loadDriveData` keeps this near-free
    /// when nothing actually came online.
    func reloadOfflineRoots() {
        for root in roots {
            let hasTracks = tracks.contains(where: { $0.rootBookmarkID == root.id })
            if !hasTracks {
                loadDriveData(for: root)
            }
        }
    }

    // MARK: - Artwork rescan (issue #77)

    /// Walks `<DriveRoot>/HarmonIQ/Artwork/` (or the local sandbox shadow for
    /// read-only roots), and adopts any `<sha1>.jpg` whose hash matches a
    /// known album on this drive. Patches `Track.artworkPath` for matching
    /// tracks, re-mirrors files to the local cache, and rewrites
    /// `library.json`.
    ///
    /// Filename convention is `sha1(albumArtist|album).jpg` — the same key
    /// the indexer and the online fetcher use. Files that don't match a
    /// known album are left alone.
    ///
    /// Returns a tuple of `(tracksUpdated, albumsAdopted)` for surfacing in UI.
    @discardableResult
    func rescanArtwork(for root: LibraryRoot) -> (tracksUpdated: Int, albumsAdopted: Int) {
        let result = performArtworkRescan(rootID: root.id, silent: false)
        artworkRescanStatus = result.message
        return (result.tracksUpdated, result.albumsAdopted)
    }

    /// Quiet variant called from drive-load. Same logic as `rescanArtwork`,
    /// but no status string update unless something changed — we don't want
    /// to overwrite the indexer's "Indexed N tracks" message on every launch.
    fileprivate func reconcileArtworkOnLoad(rootID: UUID) {
        let result = performArtworkRescan(rootID: rootID, silent: true)
        if result.tracksUpdated > 0 {
            print("[HarmonIQ] Adopted \(result.albumsAdopted) artwork file(s) on drive load — patched \(result.tracksUpdated) track row(s).")
        }
    }

    private struct ArtworkRescanResult {
        let tracksUpdated: Int
        let albumsAdopted: Int
        let message: String
    }

    private func performArtworkRescan(rootID: UUID, silent: Bool) -> ArtworkRescanResult {
        guard let root = roots.first(where: { $0.id == rootID }) else {
            return ArtworkRescanResult(tracksUpdated: 0, albumsAdopted: 0, message: "Drive not found.")
        }
        let driveTracks = tracks.filter { $0.rootBookmarkID == rootID }
        if driveTracks.isEmpty {
            return ArtworkRescanResult(tracksUpdated: 0, albumsAdopted: 0,
                                       message: "No tracks on \(root.displayName) — nothing to match.")
        }

        // Map known albums to (hash → first sample track) so we can decide
        // which on-disk files are interesting.
        var hashToAlbum: [String: (albumArtist: String?, artist: String?, album: String?)] = [:]
        for t in driveTracks {
            let key = Self.albumKey(albumArtist: t.albumArtist, artist: t.artist, album: t.album)
            let h = Self.sha1Hex(key)
            if hashToAlbum[h] == nil {
                hashToAlbum[h] = (t.albumArtist, t.artist, t.album)
            }
        }

        // Find which artwork files actually exist on disk for this drive.
        let cacheDir = artworkDirectory
        let presentHashes: Set<String>
        if root.isReadOnly {
            // Read-only roots have no on-drive Artwork folder — the local
            // cache is the source of truth.
            presentHashes = Self.scanArtworkFolder(cacheDir)
        } else {
            let driveHashes: Set<String>? = withDriveAccess(root) { driveURL in
                let driveArt = DriveLibraryStore.artworkFolder(in: driveURL)
                let hashes = Self.scanArtworkFolder(driveArt)
                // Re-mirror so the local cache reflects whatever appeared on
                // the drive between launches (manual drop, AirDrop into Files,
                // a sibling iPhone's fetcher, etc.).
                DriveLibraryStore.mirrorArtworkToLocalCache(driveRoot: driveURL, localCache: cacheDir)
                return hashes
            }
            presentHashes = driveHashes ?? []
        }

        if presentHashes.isEmpty {
            return ArtworkRescanResult(
                tracksUpdated: 0, albumsAdopted: 0,
                message: "No artwork files found on \(root.displayName)."
            )
        }

        // Patch every track on this drive whose album hash has a matching
        // file on disk and whose recorded artworkPath is missing or stale.
        var updatedCount = 0
        var adoptedHashes: Set<String> = []
        let canonical: (String) -> String = { "\($0).jpg" }
        let updatedTracks: [Track] = tracks.map { t in
            guard t.rootBookmarkID == rootID else { return t }
            let key = Self.albumKey(albumArtist: t.albumArtist, artist: t.artist, album: t.album)
            let h = Self.sha1Hex(key)
            guard presentHashes.contains(h) else { return t }
            let target = canonical(h)
            if t.artworkPath == target { return t }
            adoptedHashes.insert(h)
            updatedCount += 1
            var copy = t
            copy.artworkPath = target
            return copy
        }

        // Drop on-disk files that don't correspond to any known album from
        // the count surfaced to the user — they're harmless but shouldn't
        // be conflated with adopted ones.
        let _ = presentHashes.subtracting(adoptedHashes)

        if updatedCount == 0 {
            return ArtworkRescanResult(
                tracksUpdated: 0, albumsAdopted: 0,
                message: silent ? "" : "All artwork on \(root.displayName) was already linked."
            )
        }

        // Persist: replaceTracks rewrites library.json (or the sandbox
        // shadow). Filter to this drive's slice — replaceTracks expects
        // the full per-drive set.
        let perRoot = updatedTracks.filter { $0.rootBookmarkID == rootID }
        replaceTracks(forRoot: rootID, with: perRoot)

        let message = "Adopted \(adoptedHashes.count) album cover(s) on \(root.displayName) — patched \(updatedCount) track(s)."
        return ArtworkRescanResult(tracksUpdated: updatedCount,
                                   albumsAdopted: adoptedHashes.count,
                                   message: message)
    }

    private static func scanArtworkFolder(_ folder: URL) -> Set<String> {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folder,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles]) else { return [] }
        var out: Set<String> = []
        for entry in entries {
            let name = entry.lastPathComponent
            // Accept any extension we can render — be lenient about the
            // image format the user dropped in.
            let ext = entry.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "heic", "webp"].contains(ext) else { continue }
            let stem = (name as NSString).deletingPathExtension
            // sha1 is 40 hex chars. Anything else is ignored.
            guard stem.count == 40, stem.allSatisfy({ $0.isHexDigit }) else { continue }
            out.insert(stem)
        }
        return out
    }

    fileprivate static func albumKey(albumArtist: String?, artist: String?, album: String?) -> String {
        "\(albumArtist ?? artist ?? "Unknown")|\(album ?? "Unknown")"
    }

    fileprivate static func sha1Hex(_ s: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func writePlaylistsToDrive(rootID: UUID) {
        guard let root = roots.first(where: { $0.id == rootID }) else { return }
        let owned = playlists.filter { $0.rootBookmarkID == rootID }
        let file = DriveLibraryStore.DrivePlaylistsFile(version: 1, playlists: owned.map { DriveLibraryStore.fromPlaylist($0) })
        if root.isReadOnly {
            try? SandboxRootStore.writePlaylists(file, rootID: root.id)
            return
        }
        withDriveAccess(root) { driveURL in
            try DriveLibraryStore.writePlaylists(file, driveRoot: driveURL)
        }
    }

    // MARK: - Roots

    func addRoot(_ root: LibraryRoot) {
        if let idx = roots.firstIndex(where: { $0.id == root.id }) {
            roots[idx] = root
        } else {
            roots.append(root)
        }
        saveRoots()
        loadDriveData(for: root)
    }

    func updateRoot(_ root: LibraryRoot) {
        guard let idx = roots.firstIndex(where: { $0.id == root.id }) else { return }
        roots[idx] = root
        saveRoots()
    }

    func removeRoot(_ root: LibraryRoot) {
        roots.removeAll { $0.id == root.id }
        // Drop in-memory tracks/playlists belonging to this drive. The on-drive files
        // stay; re-adding the same drive will pick them up again. Sandbox-stored
        // index for read-only roots gets cleaned up since it's keyed by rootID.
        tracks.removeAll { $0.rootBookmarkID == root.id }
        playlists.removeAll { $0.rootBookmarkID == root.id }
        if root.isReadOnly {
            SandboxRootStore.deleteAll(rootID: root.id)
        }
        saveRoots()
    }

    // MARK: - Tracks

    /// Replace tracks for a root in memory AND persist them. For read-write roots
    /// the index is written to the drive's HarmonIQ/library.json; for read-only
    /// roots it's written to the sandbox shadow store.
    func replaceTracks(forRoot rootID: UUID, with newTracks: [Track]) {
        mergeTracks(forRoot: rootID, with: newTracks)
        if let idx = roots.firstIndex(where: { $0.id == rootID }) {
            roots[idx].lastIndexed = Date()
            roots[idx].trackCount = newTracks.count
            saveRoots()
        }
        guard let root = roots.first(where: { $0.id == rootID }) else { return }
        let file = DriveLibraryStore.DriveLibraryFile(version: 1, tracks: newTracks.map { DriveLibraryStore.fromTrack($0) })
        if root.isReadOnly {
            try? SandboxRootStore.writeLibrary(file, rootID: root.id)
            return
        }
        withDriveAccess(root) { driveURL in
            try DriveLibraryStore.writeLibrary(file, driveRoot: driveURL)
        }
    }

    private func mergeTracks(forRoot rootID: UUID, with newTracks: [Track]) {
        var preserved = tracks.filter { $0.rootBookmarkID != rootID }
        preserved.append(contentsOf: newTracks)
        preserved.sort { lhs, rhs in
            lhs.relativePath.joined(separator: "/").localizedStandardCompare(rhs.relativePath.joined(separator: "/")) == .orderedAscending
        }
        self.tracks = preserved
    }

    private func mergePlaylists(forRoot rootID: UUID, with newPlaylists: [Playlist]) {
        var preserved = playlists.filter { $0.rootBookmarkID != rootID }
        preserved.append(contentsOf: newPlaylists)
        self.playlists = preserved
    }

    func track(withID id: String) -> Track? {
        tracks.first { $0.stableID == id }
    }

    // MARK: - Playlists

    enum PlaylistError: Error {
        case noDrives
    }

    /// Creates a playlist owned by the given drive (or the first drive if unspecified).
    /// Returns nil if there are no drives — playlists are stored on a drive.
    @discardableResult
    func createPlaylist(name: String, on rootID: UUID? = nil) -> Playlist? {
        let target: UUID
        if let rootID = rootID, roots.contains(where: { $0.id == rootID }) {
            target = rootID
        } else if let first = roots.first?.id {
            target = first
        } else {
            return nil
        }
        let p = Playlist(name: name, rootBookmarkID: target)
        playlists.append(p)
        writePlaylistsToDrive(rootID: target)
        return p
    }

    func renamePlaylist(_ playlist: Playlist, to name: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].name = name
        playlists[idx].updatedAt = Date()
        writePlaylistsToDrive(rootID: playlists[idx].rootBookmarkID)
    }

    func deletePlaylist(_ playlist: Playlist) {
        guard let owner = playlists.first(where: { $0.id == playlist.id })?.rootBookmarkID else { return }
        playlists.removeAll { $0.id == playlist.id }
        writePlaylistsToDrive(rootID: owner)
    }

    func addTracks(_ trackIDs: [String], to playlist: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        for tid in trackIDs where !playlists[idx].trackIDs.contains(tid) {
            playlists[idx].trackIDs.append(tid)
        }
        playlists[idx].updatedAt = Date()
        writePlaylistsToDrive(rootID: playlists[idx].rootBookmarkID)
    }

    func removeTrack(_ trackID: String, from playlist: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].trackIDs.removeAll { $0 == trackID }
        playlists[idx].updatedAt = Date()
        writePlaylistsToDrive(rootID: playlists[idx].rootBookmarkID)
    }

    func reorderTracks(in playlist: Playlist, from source: IndexSet, to destination: Int) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].trackIDs.move(fromOffsets: source, toOffset: destination)
        playlists[idx].updatedAt = Date()
        writePlaylistsToDrive(rootID: playlists[idx].rootBookmarkID)
    }

    func tracks(for playlist: Playlist) -> [Track] {
        let map: [String: Track] = Dictionary(uniqueKeysWithValues: tracks.map { ($0.stableID, $0) })
        return playlist.trackIDs.compactMap { map[$0] }
    }

    // MARK: - Smart playlists (issue #58)

    struct SmartSaveResult {
        let playlist: Playlist
        let savedCount: Int
        let totalCount: Int
        var partial: Bool { savedCount < totalCount }
    }

    /// Save an AI-curated queue as a regular drive-resident playlist.
    /// `trackIDs` is the ordered queue. `prompt`/`mode` are stashed on the
    /// playlist so the row can show what was typed and a future Regenerate
    /// action can rebuild it.
    ///
    /// Owning drive: the drive that contains the most tracks from the
    /// queue (playlists own exactly one drive). Tracks on other drives
    /// are dropped from the saved playlist; the result reports the
    /// `savedCount` so the UI can show "Saved N of M tracks".
    @discardableResult
    func saveSmartPlaylist(name: String,
                           trackIDs: [String],
                           prompt: String?,
                           mode: String?) -> SmartSaveResult? {
        guard !trackIDs.isEmpty else { return nil }
        // Map each queue track to its owning drive so we can count.
        let trackByID: [String: Track] = Dictionary(uniqueKeysWithValues: tracks.map { ($0.stableID, $0) })
        var dropPerRoot: [UUID: [String]] = [:]
        for tid in trackIDs {
            guard let t = trackByID[tid] else { continue }
            dropPerRoot[t.rootBookmarkID, default: []].append(tid)
        }
        // Pick the drive holding the most queue tracks. Tiebreaker: first
        // mounted drive that has a positive count, in `roots` order.
        let chosen: UUID? = roots
            .map { ($0.id, dropPerRoot[$0.id]?.count ?? 0) }
            .filter { $0.1 > 0 }
            .max(by: { $0.1 < $1.1 })?.0
        guard let target = chosen else { return nil }
        let kept = dropPerRoot[target] ?? []
        // Preserve the original queue order while filtering to the chosen drive.
        let keptSet = Set(kept)
        let orderedKept = trackIDs.filter { keptSet.contains($0) }
        let p = Playlist(
            name: name,
            trackIDs: orderedKept,
            rootBookmarkID: target,
            isSmart: true,
            smartPrompt: prompt,
            smartMode: mode
        )
        playlists.append(p)
        writePlaylistsToDrive(rootID: target)
        return SmartSaveResult(playlist: p, savedCount: orderedKept.count, totalCount: trackIDs.count)
    }

    /// All AI-saved playlists, ordered by `createdAt` descending.
    var smartPlaylists: [Playlist] {
        playlists.filter { $0.isSmart }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Favorites

    /// Per-drive system Favorites playlist, if one exists for the given drive.
    func favoritesPlaylist(forRoot rootID: UUID) -> Playlist? {
        playlists.first { $0.rootBookmarkID == rootID && $0.isFavorites }
    }

    /// All Favorites playlists across mounted drives, sorted by drive display name.
    var favoritesPlaylists: [Playlist] {
        let favs = playlists.filter { $0.isFavorites }
        let nameByRoot: [UUID: String] = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0.displayName) })
        return favs.sorted { (nameByRoot[$0.rootBookmarkID] ?? "") .localizedStandardCompare(nameByRoot[$1.rootBookmarkID] ?? "") == .orderedAscending }
    }

    /// True if `track` belongs to its drive's Favorites playlist.
    func isFavorite(_ track: Track) -> Bool {
        guard let fav = favoritesPlaylist(forRoot: track.rootBookmarkID) else { return false }
        return fav.trackIDs.contains(track.stableID)
    }

    /// Toggles favorite state for a track. Auto-creates the drive's Favorites
    /// playlist on first toggle. Returns the new state (true = now favorited).
    /// No-op (returns false) if the track's drive isn't currently mounted.
    @discardableResult
    func toggleFavorite(_ track: Track) -> Bool {
        let rootID = track.rootBookmarkID
        guard roots.contains(where: { $0.id == rootID }) else { return false }
        if let fav = favoritesPlaylist(forRoot: rootID) {
            if fav.trackIDs.contains(track.stableID) {
                removeTrack(track.stableID, from: fav)
                return false
            } else {
                addTracks([track.stableID], to: fav)
                return true
            }
        } else {
            let new = Playlist(name: "Favorites", trackIDs: [track.stableID], rootBookmarkID: rootID, isFavorites: true)
            playlists.append(new)
            writePlaylistsToDrive(rootID: rootID)
            return true
        }
    }

    // MARK: - Aggregations

    var allArtists: [String] {
        let set = Set(tracks.map { $0.displayArtist })
        return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func tracks(byArtist artist: String) -> [Track] {
        tracks.filter { $0.displayArtist == artist }
    }

    struct AlbumKey: Hashable, Identifiable {
        let album: String
        let artist: String
        var id: String { "\(artist)|\(album)" }
    }

    var allAlbums: [AlbumKey] {
        var set: Set<AlbumKey> = []
        for t in tracks { set.insert(AlbumKey(album: t.displayAlbum, artist: t.displayArtist)) }
        return set.sorted { lhs, rhs in
            if lhs.album != rhs.album {
                return lhs.album.localizedStandardCompare(rhs.album) == .orderedAscending
            }
            return lhs.artist.localizedStandardCompare(rhs.artist) == .orderedAscending
        }
    }

    func tracks(forAlbum key: AlbumKey) -> [Track] {
        tracks.filter { $0.displayAlbum == key.album && $0.displayArtist == key.artist }
            .sorted { lhs, rhs in
                if let l = lhs.discNumber, let r = rhs.discNumber, l != r { return l < r }
                if let l = lhs.trackNumber, let r = rhs.trackNumber, l != r { return l < r }
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    func search(_ query: String) -> [Track] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return tracks.filter { t in
            t.displayTitle.lowercased().contains(q)
            || t.displayArtist.lowercased().contains(q)
            || t.displayAlbum.lowercased().contains(q)
        }
    }
}
