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
        let localCacheDir = LibraryStore.shared.artworkDirectory

        indexingTask = Task.detached(priority: .userInitiated) {
            await Self.runIndex(rootID: rootID, bookmark: bookmark, localCacheDir: localCacheDir)
        }
    }

    /// Heavy lifting runs off the main actor. UI updates hop back via MainActor.run.
    private static func runIndex(rootID: UUID, bookmark: Data, localCacheDir: URL) async {
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

        // Try to create the on-drive HarmonIQ/ folder. If the picker handed us
        // a read-only location (iOS system "Music", certain iCloud paths) the
        // write fails — fall back to storing the index in the app sandbox via
        // SandboxRootStore so the user can still use the drive.
        var isReadOnly = false
        do {
            try DriveLibraryStore.ensureFolders(in: resolvedURL)
        } catch let err as NSError where Self.isWritePermissionError(err) {
            isReadOnly = true
            await MainActor.run {
                MusicIndexer.shared.statusMessage = "Drive is read-only — storing index on this device."
                if var root = LibraryStore.shared.roots.first(where: { $0.id == rootID }) {
                    root.isReadOnly = true
                    LibraryStore.shared.updateRoot(root)
                }
            }
        } catch {
            await MainActor.run {
                MusicIndexer.shared.isIndexing = false
                MusicIndexer.shared.statusMessage = "Couldn't create HarmonIQ folder on drive: \(error.localizedDescription)"
            }
            return
        }
        let driveArtworkDir = DriveLibraryStore.artworkFolder(in: resolvedURL)

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
                LibraryStore.shared.replaceTracks(forRoot: rootID, with: [])
                if stale, var root = LibraryStore.shared.roots.first(where: { $0.id == rootID }) {
                    if let newBookmark = try? resolvedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        root.bookmark = newBookmark
                        LibraryStore.shared.updateRoot(root)
                    }
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
            let stableID = stableIdentifier(for: relComponents)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let fileFormat = url.pathExtension.lowercased()

            let metadata = await MetadataExtractor.extract(from: url)

            var artworkPath: String? = nil
            if let data = metadata.artworkData {
                let albumKey = "\(metadata.albumArtist ?? metadata.artist ?? "Unknown")|\(metadata.album ?? "Unknown")"
                let hash = sha1Hex(albumKey)
                let localTarget = localCacheDir.appendingPathComponent("\(hash).jpg")
                if isReadOnly {
                    // No on-drive Artwork folder — write straight to local cache.
                    if seenArtworkKeys.contains(hash) || FileManager.default.fileExists(atPath: localTarget.path) {
                        artworkPath = "\(hash).jpg"
                        seenArtworkKeys.insert(hash)
                    } else if let saved = await MetadataExtractor.saveArtworkAsync(data, named: hash, to: localCacheDir) {
                        artworkPath = saved
                        seenArtworkKeys.insert(hash)
                    }
                } else {
                    let driveTarget = driveArtworkDir.appendingPathComponent("\(hash).jpg")
                    if seenArtworkKeys.contains(hash) || FileManager.default.fileExists(atPath: driveTarget.path) {
                        artworkPath = "\(hash).jpg"
                        seenArtworkKeys.insert(hash)
                        // Best-effort mirror to local cache if it doesn't already exist there.
                        if !FileManager.default.fileExists(atPath: localTarget.path) {
                            try? FileManager.default.copyItem(at: driveTarget, to: localTarget)
                        }
                    } else if let saved = await MetadataExtractor.saveArtworkAsync(data, named: hash, to: driveArtworkDir) {
                        artworkPath = saved
                        seenArtworkKeys.insert(hash)
                        // Mirror the freshly written jpeg into the local cache.
                        if !FileManager.default.fileExists(atPath: localTarget.path) {
                            try? FileManager.default.copyItem(at: driveTarget, to: localTarget)
                        }
                    }
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
            // replaceTracks writes the on-drive library.json itself.
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
            // Ignore HarmonIQ's own folder so re-indexes don't pick up artwork as audio.
            if url.pathComponents.contains(DriveLibraryStore.folderName) { continue }
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

    /// Drive-relative track identity. Same drive on a different iPhone produces the
    /// same stableID — a prerequisite for the on-drive index to be portable.
    private static func stableIdentifier(for relComponents: [String]) -> String {
        sha1Hex(relComponents.joined(separator: "/"))
    }

    private static func sha1Hex(_ s: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func deriveTitleFromFilename(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
    }

    /// Cocoa surfaces "no permission to write" failures with a small set of error
    /// codes, plus POSIX EACCES/EPERM/EROFS passthroughs from Foundation. Treat
    /// any of those as "this folder is read-only, fall back to sandbox storage."
    private static func isWritePermissionError(_ err: NSError) -> Bool {
        if err.domain == NSCocoaErrorDomain {
            if err.code == NSFileWriteNoPermissionError || err.code == NSFileWriteVolumeReadOnlyError {
                return true
            }
        }
        if err.domain == NSPOSIXErrorDomain {
            // EACCES = 13, EPERM = 1, EROFS = 30
            if err.code == 13 || err.code == 1 || err.code == 30 { return true }
        }
        if let underlying = err.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isWritePermissionError(underlying)
        }
        return false
    }
}
