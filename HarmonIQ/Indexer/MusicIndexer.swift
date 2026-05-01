import Foundation
import Combine
import CryptoKit

@MainActor
final class MusicIndexer: ObservableObject {
    static let shared = MusicIndexer()

    @Published var isIndexing: Bool = false
    @Published var statusMessage: String = ""
    @Published var progress: Double = 0
    @Published var processed: Int = 0
    @Published var totalToProcess: Int = 0

    private var indexingTask: Task<Void, Never>?

    func cancel() {
        indexingTask?.cancel()
        indexingTask = nil
        isIndexing = false
        statusMessage = "Cancelled"
    }

    func index(root: LibraryRoot) {
        guard !isIndexing else { return }
        isIndexing = true
        progress = 0
        processed = 0
        totalToProcess = 0
        statusMessage = "Starting indexing…"

        let bookmark = root.bookmark
        let rootID = root.id
        let artworkDir = LibraryStore.shared.artworkDirectory

        indexingTask = Task.detached(priority: .userInitiated) {
            await Self.runIndex(rootID: rootID, bookmark: bookmark, artworkDir: artworkDir)
        }
    }

    /// Heavy lifting runs off the main actor. UI updates hop back via MainActor.run.
    private static func runIndex(rootID: UUID, bookmark: Data, artworkDir: URL) async {
        await MainActor.run {
            MusicIndexer.shared.statusMessage = "Resolving access to drive…"
        }

        var stale = false
        let resolvedURL: URL
        do {
            resolvedURL = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            await MainActor.run {
                MusicIndexer.shared.isIndexing = false
                MusicIndexer.shared.statusMessage = "Couldn't resolve drive: \(error.localizedDescription)"
            }
            return
        }

        let started = resolvedURL.startAccessingSecurityScopedResource()
        defer { if started { resolvedURL.stopAccessingSecurityScopedResource() } }

        await MainActor.run { MusicIndexer.shared.statusMessage = "Scanning folders…" }
        let urls = scanForAudioFiles(under: resolvedURL)

        await MainActor.run {
            MusicIndexer.shared.totalToProcess = urls.count
            MusicIndexer.shared.statusMessage = "Found \(urls.count) audio files. Reading metadata…"
        }

        if urls.isEmpty {
            await MainActor.run {
                MusicIndexer.shared.isIndexing = false
                MusicIndexer.shared.progress = 1
                MusicIndexer.shared.statusMessage = "No audio files found on this drive."
                if var root = LibraryStore.shared.roots.first(where: { $0.id == rootID }) {
                    root.lastIndexed = Date()
                    root.trackCount = 0
                    if stale, let newBookmark = try? resolvedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        root.bookmark = newBookmark
                    }
                    LibraryStore.shared.updateRoot(root)
                }
            }
            return
        }

        var tracks: [Track] = []
        tracks.reserveCapacity(urls.count)
        let rootPathComponents = resolvedURL.pathComponents
        var seenArtworkKeys: Set<String> = []

        for (idx, url) in urls.enumerated() {
            if Task.isCancelled { break }

            let relComponents = relativePathComponents(of: url, fromRoot: rootPathComponents)
            let stableID = stableIdentifier(for: relComponents, rootID: rootID)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let fileFormat = url.pathExtension.lowercased()

            let metadata = await MetadataExtractor.extract(from: url)

            var artworkPath: String? = nil
            if let data = metadata.artworkData {
                let albumKey = "\(metadata.albumArtist ?? metadata.artist ?? "Unknown")|\(metadata.album ?? "Unknown")"
                let hash = sha1Hex(albumKey)
                let target = artworkDir.appendingPathComponent("\(hash).jpg")
                if seenArtworkKeys.contains(hash) || FileManager.default.fileExists(atPath: target.path) {
                    artworkPath = "\(hash).jpg"
                    seenArtworkKeys.insert(hash)
                } else {
                    artworkPath = await MetadataExtractor.saveArtworkAsync(data, named: hash, to: artworkDir)
                    if artworkPath != nil { seenArtworkKeys.insert(hash) }
                }
            }

            let track = Track(
                id: UUID(),
                stableID: stableID,
                relativePath: relComponents,
                filename: url.lastPathComponent,
                rootBookmarkID: rootID,
                fileBookmark: nil,
                title: metadata.title ?? deriveTitleFromFilename(url),
                artist: metadata.artist,
                album: metadata.album,
                albumArtist: metadata.albumArtist,
                genre: metadata.genre,
                year: metadata.year,
                trackNumber: metadata.trackNumber,
                discNumber: metadata.discNumber,
                duration: metadata.duration,
                fileSize: fileSize,
                fileFormat: fileFormat,
                artworkPath: artworkPath
            )
            tracks.append(track)

            let processed = idx + 1
            let total = urls.count
            if processed % 5 == 0 || processed == total {
                await MainActor.run {
                    MusicIndexer.shared.processed = processed
                    MusicIndexer.shared.totalToProcess = total
                    MusicIndexer.shared.progress = total > 0 ? Double(processed) / Double(total) : 1
                    MusicIndexer.shared.statusMessage = "Indexed \(processed) of \(total)"
                }
            }
        }

        let collected = tracks
        await MainActor.run {
            LibraryStore.shared.replaceTracks(forRoot: rootID, with: collected)
            if stale, var root = LibraryStore.shared.roots.first(where: { $0.id == rootID }) {
                if let newBookmark = try? resolvedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    root.bookmark = newBookmark
                    LibraryStore.shared.updateRoot(root)
                }
            }
            MusicIndexer.shared.isIndexing = false
            MusicIndexer.shared.progress = 1
            MusicIndexer.shared.statusMessage = "Indexed \(collected.count) tracks."
        }
    }

    // MARK: - File walking (nonisolated helpers)

    private static func scanForAudioFiles(under root: URL) -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true, MetadataExtractor.isSupported(url) {
                results.append(url)
            }
        }
        return results
    }

    private static func relativePathComponents(of url: URL, fromRoot rootComponents: [String]) -> [String] {
        let urlComponents = url.pathComponents
        if urlComponents.count > rootComponents.count,
           Array(urlComponents.prefix(rootComponents.count)) == rootComponents {
            return Array(urlComponents.dropFirst(rootComponents.count))
        }
        return [url.lastPathComponent]
    }

    private static func stableIdentifier(for relComponents: [String], rootID: UUID) -> String {
        let raw = "\(rootID.uuidString)/\(relComponents.joined(separator: "/"))"
        return sha1Hex(raw)
    }

    private static func sha1Hex(_ s: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func deriveTitleFromFilename(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
    }
}
