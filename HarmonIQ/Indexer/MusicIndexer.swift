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

    /// Kick off an index run. When `force` is true the cheap fingerprint
    /// short-circuit is skipped and the full incremental walk always runs —
    /// this is the contract the UI's explicit Reindex button relies on, so
    /// tapping it never silently no-ops.
    func index(root: LibraryRoot, force: Bool = false) {
        guard !isIndexing else { return }
        isIndexing = true
        progress = 0
        processed = 0
        totalToProcess = 0
        statusMessage = "Starting indexing…"

        let bookmark = root.bookmark
        let rootID = root.id
        let priorFingerprint = force ? nil : root.lastScanFingerprint
        let localCacheDir = LibraryStore.shared.artworkDirectory
        let priorTracks = LibraryStore.shared.tracks.filter { $0.rootBookmarkID == rootID }

        indexingTask = Task.detached(priority: .userInitiated) {
            await Self.runIndex(rootID: rootID,
                                bookmark: bookmark,
                                priorFingerprint: priorFingerprint,
                                priorTracks: priorTracks,
                                localCacheDir: localCacheDir)
        }
    }

    /// Heavy lifting runs off the main actor. UI updates hop back via MainActor.run.
    private static func runIndex(rootID: UUID,
                                 bookmark: Data,
                                 priorFingerprint: ScanFingerprint?,
                                 priorTracks: [Track],
                                 localCacheDir: URL) async {
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

        // Cheap top-level fingerprint check. If the drive root's mtime AND
        // child count both match the last scan AND we already have tracks
        // loaded for this drive, declare "Up to date" and skip the walk.
        // Skipping the cheap-check when priorTracks is empty matters when
        // the drive's library.json was missing or empty — the fingerprint
        // could match by luck, and we'd incorrectly say "0 tracks, all
        // good." Caveat: in-place file edits (tag changes without rename)
        // don't bump folder mtime; user can hit Reindex (which now passes
        // force=true and skips this whole block).
        if let fingerprint = priorFingerprint,
           !priorTracks.isEmpty,
           let current = computeFingerprint(rootURL: resolvedURL),
           current == fingerprint {
            await MainActor.run {
                MusicIndexer.shared.isIndexing = false
                MusicIndexer.shared.progress = 1
                MusicIndexer.shared.statusMessage = "Up to date — \(priorTracks.count) tracks."
            }
            return
        }

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
                writebackFingerprint(rootID: rootID, rootURL: resolvedURL, stale: stale)
            }
            return
        }

        // Build the prior-tracks lookup once. Stored Track rows are keyed by
        // stableID (sha1 of relative path).
        let priorByID: [String: Track] = Dictionary(uniqueKeysWithValues: priorTracks.map { ($0.stableID, $0) })

        var tracks: [Track] = []
        tracks.reserveCapacity(urls.count)
        let rootPathComponents = resolvedURL.pathComponents
        var seenArtworkKeys: Set<String> = []
        var added = 0
        var updated = 0
        var unchanged = 0

        for (idx, url) in urls.enumerated() {
            if Task.isCancelled { break }

            let relComponents = relativePathComponents(of: url, fromRoot: rootPathComponents)
            let stableID = stableIdentifier(for: relComponents)
            let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = resourceValues?.contentModificationDate
            let fileSize = Int64((resourceValues?.fileSize) ?? 0)
            let fileFormat = url.pathExtension.lowercased()

            // Reuse path: existing row whose stored mtime matches the file's
            // current mtime. Saves the metadata-extraction + artwork-hash
            // round trip — the most expensive per-file work in this loop.
            if let existing = priorByID[stableID],
               let storedMtime = existing.fileModified,
               let mtime = mtime,
               abs(storedMtime.timeIntervalSince(mtime)) < 1 {
                tracks.append(existing)
                unchanged += 1
                if let path = existing.artworkPath {
                    seenArtworkKeys.insert((path as NSString).deletingPathExtension)
                }
                let processed = idx + 1
                if processed % 25 == 0 || processed == urls.count {
                    await MainActor.run {
                        MusicIndexer.shared.processed = processed
                        MusicIndexer.shared.totalToProcess = urls.count
                        MusicIndexer.shared.progress = Double(processed) / Double(urls.count)
                        MusicIndexer.shared.statusMessage = "Scanning — \(processed)/\(urls.count)"
                    }
                }
                continue
            }

            // Either new (no prior row) or mtime changed → re-extract.
            let metadata = await MetadataExtractor.extract(from: url)

            var artworkPath: String? = nil
            if let data = metadata.artworkData {
                let albumKey = "\(metadata.albumArtist ?? metadata.artist ?? "Unknown")|\(metadata.album ?? "Unknown")"
                let hash = sha1Hex(albumKey)
                let localTarget = localCacheDir.appendingPathComponent("\(hash).jpg")
                if isReadOnly {
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
                        if !FileManager.default.fileExists(atPath: localTarget.path) {
                            try? FileManager.default.copyItem(at: driveTarget, to: localTarget)
                        }
                    } else if let saved = await MetadataExtractor.saveArtworkAsync(data, named: hash, to: driveArtworkDir) {
                        artworkPath = saved
                        seenArtworkKeys.insert(hash)
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
                artworkPath: artworkPath,
                fileModified: mtime
            )
            tracks.append(track)
            if priorByID[stableID] == nil { added += 1 } else { updated += 1 }

            let processed = idx + 1
            if processed % 5 == 0 || processed == urls.count {
                await MainActor.run {
                    MusicIndexer.shared.processed = processed
                    MusicIndexer.shared.totalToProcess = urls.count
                    MusicIndexer.shared.progress = Double(processed) / Double(urls.count)
                    MusicIndexer.shared.statusMessage = "Indexed \(processed) of \(urls.count)"
                }
            }
        }

        let removed = max(0, priorTracks.count - unchanged - updated)
        let collected = tracks
        let summaryAdded = added
        let summaryUpdated = updated
        let summaryRemoved = removed
        await MainActor.run {
            // replaceTracks writes the on-drive library.json itself.
            LibraryStore.shared.replaceTracks(forRoot: rootID, with: collected)
            writebackFingerprint(rootID: rootID, rootURL: resolvedURL, stale: stale)
            MusicIndexer.shared.isIndexing = false
            MusicIndexer.shared.progress = 1
            if summaryAdded == 0 && summaryUpdated == 0 && summaryRemoved == 0 {
                MusicIndexer.shared.statusMessage = "Up to date — \(collected.count) tracks."
            } else {
                var parts: [String] = []
                if summaryAdded > 0 { parts.append("\(summaryAdded) new") }
                if summaryUpdated > 0 { parts.append("\(summaryUpdated) updated") }
                if summaryRemoved > 0 { parts.append("\(summaryRemoved) removed") }
                MusicIndexer.shared.statusMessage = "Indexed \(collected.count) tracks (\(parts.joined(separator: ", "))).";
            }
        }
    }

    /// Persist the new fingerprint + bookmark on the LibraryRoot. Run on
    /// the main actor (needs LibraryStore).
    @MainActor
    private static func writebackFingerprint(rootID: UUID, rootURL: URL, stale: Bool) {
        guard var root = LibraryStore.shared.roots.first(where: { $0.id == rootID }) else { return }
        if stale, let newBookmark = try? rootURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            root.bookmark = newBookmark
        }
        if let fp = computeFingerprint(rootURL: rootURL) {
            root.lastScanFingerprint = fp
        }
        LibraryStore.shared.updateRoot(root)
    }

    /// Cheap fingerprint: drive root's mtime + immediate-child count.
    /// Returns nil when the FS metadata can't be read.
    nonisolated private static func computeFingerprint(rootURL: URL) -> ScanFingerprint? {
        let fm = FileManager.default
        let rootValues = try? rootURL.resourceValues(forKeys: [.contentModificationDateKey])
        guard let mtime = rootValues?.contentModificationDate else { return nil }
        let children = (try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        // Exclude HarmonIQ's own folder so writing the artwork cache doesn't
        // invalidate the fingerprint.
        let count = children.filter { $0.lastPathComponent != DriveLibraryStore.folderName }.count
        return ScanFingerprint(rootMtime: mtime, childCount: count)
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
