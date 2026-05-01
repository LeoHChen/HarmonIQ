import Foundation
import Combine
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var roots: [LibraryRoot] = []
    @Published private(set) var playlists: [Playlist] = []

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

    /// Loads tracks + playlists from the drive's HarmonIQ folder into the in-memory
    /// state and mirrors artwork into the local cache. No-op if the drive is offline
    /// or has no HarmonIQ folder yet.
    private func loadDriveData(for root: LibraryRoot) {
        let cacheDir = artworkDirectory
        let result = withDriveAccess(root) { driveURL -> (DriveLibraryStore.DriveLibraryFile?, DriveLibraryStore.DrivePlaylistsFile?) in
            let lib = DriveLibraryStore.loadLibrary(driveRoot: driveURL)
            let pls = DriveLibraryStore.loadPlaylists(driveRoot: driveURL)
            DriveLibraryStore.mirrorArtworkToLocalCache(driveRoot: driveURL, localCache: cacheDir)
            return (lib, pls)
        }
        guard let (lib, pls) = result else { return }

        if let lib = lib {
            let mapped = lib.tracks.map { DriveLibraryStore.toTrack($0, rootBookmarkID: root.id) }
            mergeTracks(forRoot: root.id, with: mapped)
        }
        if let pls = pls {
            let mapped = pls.playlists.map { DriveLibraryStore.toPlaylist($0, rootBookmarkID: root.id) }
            mergePlaylists(forRoot: root.id, with: mapped)
        }
    }

    private func writePlaylistsToDrive(rootID: UUID) {
        guard let root = roots.first(where: { $0.id == rootID }) else { return }
        let owned = playlists.filter { $0.rootBookmarkID == rootID }
        let file = DriveLibraryStore.DrivePlaylistsFile(version: 1, playlists: owned.map { DriveLibraryStore.fromPlaylist($0) })
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
        // stay; re-adding the same drive will pick them up again.
        tracks.removeAll { $0.rootBookmarkID == root.id }
        playlists.removeAll { $0.rootBookmarkID == root.id }
        saveRoots()
    }

    // MARK: - Tracks

    /// Replace tracks for a root in memory AND write them to the drive's library.json.
    /// Called by the indexer after a fresh scan.
    func replaceTracks(forRoot rootID: UUID, with newTracks: [Track]) {
        mergeTracks(forRoot: rootID, with: newTracks)
        if let idx = roots.firstIndex(where: { $0.id == rootID }) {
            roots[idx].lastIndexed = Date()
            roots[idx].trackCount = newTracks.count
            saveRoots()
        }
        guard let root = roots.first(where: { $0.id == rootID }) else { return }
        let file = DriveLibraryStore.DriveLibraryFile(version: 1, tracks: newTracks.map { DriveLibraryStore.fromTrack($0) })
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
