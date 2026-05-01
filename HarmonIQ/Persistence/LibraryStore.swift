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

    private var libraryFileURL: URL {
        let dir = appSupportDirectory()
        return dir.appendingPathComponent("library.json")
    }

    private var playlistsFileURL: URL {
        let dir = appSupportDirectory()
        return dir.appendingPathComponent("playlists.json")
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

    var artworkDirectory: URL {
        let dir = appSupportDirectory().appendingPathComponent("Artwork", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Persistence

    private struct LibraryFile: Codable {
        var roots: [LibraryRoot]
        var tracks: [Track]
    }

    func loadFromDisk() async {
        let libURL = libraryFileURL
        let plURL = playlistsFileURL
        let (loadedRoots, loadedTracks, loadedPlaylists): ([LibraryRoot], [Track], [Playlist]) = await withCheckedContinuation { cont in
            queue.async {
                let decoder = JSONDecoder()
                var roots: [LibraryRoot] = []
                var tracks: [Track] = []
                var playlists: [Playlist] = []
                if let data = try? Data(contentsOf: libURL),
                   let lib = try? decoder.decode(LibraryFile.self, from: data) {
                    roots = lib.roots
                    tracks = lib.tracks
                }
                if let data = try? Data(contentsOf: plURL),
                   let pls = try? decoder.decode([Playlist].self, from: data) {
                    playlists = pls
                }
                cont.resume(returning: (roots, tracks, playlists))
            }
        }
        self.roots = loadedRoots
        self.tracks = loadedTracks
        self.playlists = loadedPlaylists
    }

    func saveLibrary() {
        let snapshot = LibraryFile(roots: roots, tracks: tracks)
        let url = libraryFileURL
        queue.async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func savePlaylists() {
        let snapshot = playlists
        let url = playlistsFileURL
        queue.async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Roots

    func addRoot(_ root: LibraryRoot) {
        if let idx = roots.firstIndex(where: { $0.id == root.id }) {
            roots[idx] = root
        } else {
            roots.append(root)
        }
        saveLibrary()
    }

    func updateRoot(_ root: LibraryRoot) {
        guard let idx = roots.firstIndex(where: { $0.id == root.id }) else { return }
        roots[idx] = root
        saveLibrary()
    }

    func removeRoot(_ root: LibraryRoot) {
        roots.removeAll { $0.id == root.id }
        tracks.removeAll { $0.rootBookmarkID == root.id }
        saveLibrary()
    }

    // MARK: - Tracks

    func replaceTracks(forRoot rootID: UUID, with newTracks: [Track]) {
        var preserved = tracks.filter { $0.rootBookmarkID != rootID }
        preserved.append(contentsOf: newTracks)
        preserved.sort { lhs, rhs in
            let l = lhs.relativePath.joined(separator: "/").localizedStandardCompare(rhs.relativePath.joined(separator: "/"))
            return l == .orderedAscending
        }
        self.tracks = preserved
        if let idx = roots.firstIndex(where: { $0.id == rootID }) {
            roots[idx].lastIndexed = Date()
            roots[idx].trackCount = newTracks.count
        }
        saveLibrary()
    }

    func track(withID id: String) -> Track? {
        tracks.first { $0.stableID == id }
    }

    // MARK: - Playlists

    func createPlaylist(name: String) -> Playlist {
        let p = Playlist(name: name)
        playlists.append(p)
        savePlaylists()
        return p
    }

    func renamePlaylist(_ playlist: Playlist, to name: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].name = name
        playlists[idx].updatedAt = Date()
        savePlaylists()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        savePlaylists()
    }

    func addTracks(_ trackIDs: [String], to playlist: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        for tid in trackIDs where !playlists[idx].trackIDs.contains(tid) {
            playlists[idx].trackIDs.append(tid)
        }
        playlists[idx].updatedAt = Date()
        savePlaylists()
    }

    func removeTrack(_ trackID: String, from playlist: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].trackIDs.removeAll { $0 == trackID }
        playlists[idx].updatedAt = Date()
        savePlaylists()
    }

    func reorderTracks(in playlist: Playlist, from source: IndexSet, to destination: Int) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].trackIDs.move(fromOffsets: source, toOffset: destination)
        playlists[idx].updatedAt = Date()
        savePlaylists()
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
