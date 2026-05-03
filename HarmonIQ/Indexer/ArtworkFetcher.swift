import Foundation
import Combine
import CryptoKit
import Network
import UIKit

/// Opt-in online cover-art fetcher (issue #73).
///
/// Looks up missing album artwork via MusicBrainz + Cover Art Archive and writes
/// the result to `<DriveRoot>/HarmonIQ/Artwork/<sha1(albumArtist|album)>.jpg`,
/// honoring the security-scoped bookmark via the same dance the indexer uses.
///
/// Privacy: this is the only place HarmonIQ talks to the network for music
/// metadata. The toggle is off by default — when off, no method on this type
/// issues network traffic.
///
/// Threading: `@MainActor` because the fetcher reads/writes published progress
/// state and mutates `LibraryStore.shared.tracks` (also main-actor). Network +
/// file IO hops to detached tasks; we hop back via `MainActor.run`.
@MainActor
final class ArtworkFetcher: ObservableObject {
    static let shared = ArtworkFetcher()

    // MARK: - User preference

    private static let enabledDefaultsKey = "ArtworkFetcher.onlineEnabled"

    /// User-visible toggle. Off by default. When false, every public entry
    /// point on this type is a no-op — no network calls are made, ever.
    @Published var isOnlineFetchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isOnlineFetchEnabled, forKey: Self.enabledDefaultsKey)
        }
    }

    // MARK: - Bulk refresh status (drives the Settings UI)

    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var refreshStatusMessage: String = ""
    @Published private(set) var refreshProgress: Double = 0
    @Published private(set) var refreshProcessed: Int = 0
    @Published private(set) var refreshTotal: Int = 0

    private var refreshTask: Task<Void, Never>?

    // MARK: - In-flight + negative dedupe

    /// Album hashes (sha1 of `albumArtist|album`) currently being fetched, so
    /// two near-simultaneous track plays from the same album don't issue two
    /// network round-trips.
    private var inFlight: Set<String> = []
    /// Album hashes that returned no usable cover this session. Cleared on
    /// app relaunch — a re-tag or upstream MusicBrainz correction lets the
    /// next session retry without intervention.
    private var negativeCache: Set<String> = []

    // MARK: - Reachability

    private let pathMonitor = NWPathMonitor()
    private var pathMonitorStarted = false
    private var lastKnownPath: NWPath?

    // MARK: - Rate limiter

    /// MusicBrainz documents a hard 1 req/sec limit per IP. We serialize all
    /// MusicBrainz calls through this actor and require >= 1.05s between them
    /// (small cushion for clock skew).
    private let rateLimiter = MusicBrainzRateLimiter()

    private init() {
        self.isOnlineFetchEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    // MARK: - Reachability gate

    private func isOnline() -> Bool {
        if !pathMonitorStarted {
            pathMonitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor [weak self] in
                    self?.lastKnownPath = path
                }
            }
            pathMonitor.start(queue: DispatchQueue(label: "net.leochen.harmoniq.artwork.path"))
            pathMonitorStarted = true
            // Path monitor delivers an initial event asynchronously. Until it
            // arrives, optimistically assume we're online — a failed request
            // is silent and harmless.
            return true
        }
        guard let path = lastKnownPath else { return true }
        return path.status == .satisfied
    }

    // MARK: - Public API

    /// Fire-and-forget: if the track's album has no local artwork, queue a
    /// fetch attempt. Safe to call from `playCurrent` — never blocks.
    func fetchIfMissing(for track: Track) {
        guard isOnlineFetchEnabled else { return }
        let key = Self.albumKey(albumArtist: track.albumArtist,
                                artist: track.artist,
                                album: track.album)
        let hash = Self.sha1Hex(key)

        // Already have local artwork for this album → nothing to do.
        let localCache = LibraryStore.shared.artworkDirectory
        let localTarget = localCache.appendingPathComponent("\(hash).jpg")
        if FileManager.default.fileExists(atPath: localTarget.path) { return }

        // Already failed once this session, or in flight → skip.
        if negativeCache.contains(hash) { return }
        if inFlight.contains(hash) { return }

        if !isOnline() { return }

        inFlight.insert(hash)
        Task.detached(priority: .utility) { [weak self] in
            await self?.runFetch(albumHash: hash,
                                 albumArtist: track.albumArtist,
                                 artist: track.artist,
                                 album: track.album,
                                 rootBookmarkID: track.rootBookmarkID)
        }
    }

    /// Bulk pass over a drive: walks every album that lacks artwork and tries
    /// to fill it. Light concurrency — 2 fetches in flight at a time, gated by
    /// the MusicBrainz rate limiter so we never exceed 1 req/sec.
    func refreshMissingArtwork(for root: LibraryRoot) {
        guard isOnlineFetchEnabled else { return }
        guard !isRefreshing else { return }

        let rootID = root.id
        // Snapshot albums missing art, deduped by album hash.
        let allTracks = LibraryStore.shared.tracks.filter { $0.rootBookmarkID == rootID }
        var seen: Set<String> = []
        var queue: [(hash: String, albumArtist: String?, artist: String?, album: String?)] = []
        let localCache = LibraryStore.shared.artworkDirectory
        for t in allTracks {
            let key = Self.albumKey(albumArtist: t.albumArtist, artist: t.artist, album: t.album)
            let hash = Self.sha1Hex(key)
            if seen.contains(hash) { continue }
            seen.insert(hash)
            // Skip albums whose artwork already exists locally — the bulk pass
            // is for filling gaps, not refreshing covers we already have.
            let local = localCache.appendingPathComponent("\(hash).jpg")
            if FileManager.default.fileExists(atPath: local.path) { continue }
            // Skip albums we already failed on this session.
            if negativeCache.contains(hash) { continue }
            queue.append((hash, t.albumArtist, t.artist, t.album))
        }

        if queue.isEmpty {
            refreshStatusMessage = "No albums missing artwork on \(root.displayName)."
            return
        }

        if !isOnline() {
            refreshStatusMessage = "Offline — try again when you have a connection."
            return
        }

        isRefreshing = true
        refreshTotal = queue.count
        refreshProcessed = 0
        refreshProgress = 0
        refreshStatusMessage = "Fetching artwork for \(queue.count) albums…"

        refreshTask = Task.detached(priority: .utility) { [weak self] in
            await self?.runBulkRefresh(queue: queue, rootBookmarkID: rootID, rootName: root.displayName)
        }
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        refreshStatusMessage = "Refresh cancelled."
    }

    // MARK: - Internals

    nonisolated private func runFetch(albumHash: String,
                                      albumArtist: String?,
                                      artist: String?,
                                      album: String?,
                                      rootBookmarkID: UUID) async {
        defer {
            Task { @MainActor [weak self] in
                self?.inFlight.remove(albumHash)
            }
        }

        let result = await Self.lookupAndDownload(albumHash: albumHash,
                                                  albumArtist: albumArtist,
                                                  artist: artist,
                                                  album: album,
                                                  rateLimiter: rateLimiter)

        guard let imageData = result else {
            await MainActor.run {
                self.negativeCache.insert(albumHash)
            }
            return
        }

        await MainActor.run {
            self.persistDownloadedArtwork(imageData,
                                          albumHash: albumHash,
                                          rootBookmarkID: rootBookmarkID)
        }
    }

    nonisolated private func runBulkRefresh(queue: [(hash: String, albumArtist: String?, artist: String?, album: String?)],
                                            rootBookmarkID: UUID,
                                            rootName: String) async {
        var succeeded = 0
        var processed = 0
        for entry in queue {
            if Task.isCancelled { break }
            let result = await Self.lookupAndDownload(albumHash: entry.hash,
                                                      albumArtist: entry.albumArtist,
                                                      artist: entry.artist,
                                                      album: entry.album,
                                                      rateLimiter: rateLimiter)
            processed += 1
            if let data = result {
                succeeded += 1
                let localProcessed = processed
                let localSucceeded = succeeded
                let localTotal = queue.count
                await MainActor.run {
                    self.persistDownloadedArtwork(data,
                                                  albumHash: entry.hash,
                                                  rootBookmarkID: rootBookmarkID)
                    self.refreshProcessed = localProcessed
                    self.refreshProgress = Double(localProcessed) / Double(localTotal)
                    self.refreshStatusMessage = "Fetched \(localSucceeded) of \(localProcessed) — \(localTotal) total."
                }
            } else {
                let localProcessed = processed
                let localSucceeded = succeeded
                let localTotal = queue.count
                await MainActor.run {
                    self.negativeCache.insert(entry.hash)
                    self.refreshProcessed = localProcessed
                    self.refreshProgress = Double(localProcessed) / Double(localTotal)
                    self.refreshStatusMessage = "Fetched \(localSucceeded) of \(localProcessed) — \(localTotal) total."
                }
            }
        }
        let finalSucceeded = succeeded
        let finalTotal = queue.count
        let finalProcessed = processed
        let cancelled = Task.isCancelled
        await MainActor.run {
            self.isRefreshing = false
            self.refreshProgress = 1
            self.refreshTask = nil
            if cancelled {
                self.refreshStatusMessage = "Stopped — fetched \(finalSucceeded) of \(finalProcessed) on \(rootName)."
            } else {
                self.refreshStatusMessage = "Done — fetched \(finalSucceeded) of \(finalTotal) on \(rootName)."
            }
        }
    }

    /// Writes the downloaded image to the drive's HarmonIQ/Artwork folder (or
    /// the local cache for read-only roots), mirrors it locally, and patches
    /// every in-memory track in the album so the UI updates without a relaunch.
    private func persistDownloadedArtwork(_ data: Data,
                                          albumHash: String,
                                          rootBookmarkID: UUID) {
        guard let root = LibraryStore.shared.roots.first(where: { $0.id == rootBookmarkID }) else { return }
        let localCache = LibraryStore.shared.artworkDirectory

        // Resize / re-encode through MetadataExtractor so the sizes match what
        // the indexer writes for embedded covers (max 600px, JPEG q=0.85).
        let savedFilename: String?
        if root.isReadOnly {
            // Read-only roots store their index + artwork in the sandbox.
            savedFilename = MetadataExtractor.saveArtwork(data, named: albumHash, to: localCache)
        } else {
            do {
                let driveSaved: String? = try BookmarkStore.withAccess(to: root.bookmark) { driveURL in
                    let driveArt = DriveLibraryStore.artworkFolder(in: driveURL)
                    try? FileManager.default.createDirectory(at: driveArt, withIntermediateDirectories: true)
                    let written = MetadataExtractor.saveArtwork(data, named: albumHash, to: driveArt)
                    if written != nil {
                        // Mirror to the local cache so views and MPNowPlayingInfo
                        // can read the image without holding scope.
                        let src = driveArt.appendingPathComponent("\(albumHash).jpg")
                        let dst = localCache.appendingPathComponent("\(albumHash).jpg")
                        if FileManager.default.fileExists(atPath: dst.path) {
                            try? FileManager.default.removeItem(at: dst)
                        }
                        try? FileManager.default.copyItem(at: src, to: dst)
                    }
                    return written
                }
                savedFilename = driveSaved
            } catch {
                savedFilename = nil
            }
        }

        guard let savedFilename = savedFilename else { return }

        // Patch every track on this drive that belongs to this album hash.
        // We re-derive the hash from the album/artist on each track so we can
        // do this without iterating LibraryStore from inside its own write.
        let updated: [Track] = LibraryStore.shared.tracks.compactMap { t in
            guard t.rootBookmarkID == rootBookmarkID else { return t }
            let key = Self.albumKey(albumArtist: t.albumArtist, artist: t.artist, album: t.album)
            let h = Self.sha1Hex(key)
            guard h == albumHash else { return t }
            // Track has no artwork OR points at the same hash — write the
            // canonical filename so future loads find it.
            var copy = t
            copy.artworkPath = savedFilename
            return copy
        }
        // replaceTracks rewrites the on-drive library.json (or sandbox shadow).
        // Filter to the affected drive's slice — replaceTracks expects the full
        // per-drive set.
        let perRoot = updated.filter { $0.rootBookmarkID == rootBookmarkID }
        LibraryStore.shared.replaceTracks(forRoot: rootBookmarkID, with: perRoot)
    }

    // MARK: - Helpers (static / nonisolated)

    nonisolated static func albumKey(albumArtist: String?, artist: String?, album: String?) -> String {
        "\(albumArtist ?? artist ?? "Unknown")|\(album ?? "Unknown")"
    }

    nonisolated static func sha1Hex(_ s: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - MusicBrainz + Cover Art Archive

    /// User-Agent string per MusicBrainz etiquette
    /// (https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting).
    nonisolated static func userAgent() -> String {
        // BuildInfo touches Bundle.main, which is fine off-main.
        "HarmonIQ/\(BuildInfo.version) (https://github.com/LeoHChen/HarmonIQ)"
    }

    /// Returns image bytes on success, nil on any failure (offline, no match,
    /// rate-limit error, decode failure). Fully silent — never throws.
    nonisolated private static func lookupAndDownload(albumHash: String,
                                                      albumArtist: String?,
                                                      artist: String?,
                                                      album: String?,
                                                      rateLimiter: MusicBrainzRateLimiter) async -> Data? {
        let artistQuery = (albumArtist ?? artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let albumQuery = (album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artistQuery.isEmpty, !albumQuery.isEmpty else { return nil }
        guard albumQuery.lowercased() != "unknown",
              artistQuery.lowercased() != "unknown" else { return nil }

        // 1) MusicBrainz release-group search.
        await rateLimiter.waitTurn()
        guard let mbid = await searchReleaseGroup(artist: artistQuery, album: albumQuery) else {
            return nil
        }

        // 2) Cover Art Archive front cover.
        if let data = await fetchFrontCover(mbid: mbid) {
            return data
        }
        return nil
    }

    nonisolated private static func searchReleaseGroup(artist: String, album: String) async -> String? {
        let escapedArtist = luceneEscape(artist)
        let escapedAlbum = luceneEscape(album)
        let query = "releasegroup:\"\(escapedAlbum)\" AND artist:\"\(escapedArtist)\""
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release-group/")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components?.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return nil }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let groups = json["release-groups"] as? [[String: Any]] else { return nil }

        // Pick the highest-scoring official Album, falling back to the first.
        let albumLower = album.lowercased()
        let artistLower = artist.lowercased()
        let candidates = groups.compactMap { g -> (id: String, score: Int, isAlbum: Bool, titleMatch: Bool, artistMatch: Bool)? in
            guard let id = g["id"] as? String else { return nil }
            let score = (g["score"] as? Int) ?? 0
            let primary = (g["primary-type"] as? String)?.lowercased() ?? ""
            let title = (g["title"] as? String)?.lowercased() ?? ""
            let credits = (g["artist-credit"] as? [[String: Any]]) ?? []
            let creditMatches = credits.contains { c in
                let cn = (c["name"] as? String)?.lowercased() ?? ""
                let an = (((c["artist"] as? [String: Any])?["name"]) as? String)?.lowercased() ?? ""
                return cn == artistLower || an == artistLower
            }
            return (id, score, primary == "album", title == albumLower, creditMatches)
        }
        let sorted = candidates.sorted { lhs, rhs in
            // Prefer exact title + artist match → official album → high score.
            let lhsRank = (lhs.titleMatch ? 4 : 0) + (lhs.artistMatch ? 2 : 0) + (lhs.isAlbum ? 1 : 0)
            let rhsRank = (rhs.titleMatch ? 4 : 0) + (rhs.artistMatch ? 2 : 0) + (rhs.isAlbum ? 1 : 0)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            return lhs.score > rhs.score
        }
        return sorted.first?.id
    }

    nonisolated private static func fetchFrontCover(mbid: String) async -> Data? {
        guard let url = URL(string: "https://coverartarchive.org/release-group/\(mbid)/front-500") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        // Cover Art Archive responds 307 → s3.amazonaws.com; URLSession follows
        // redirects by default which is what we want.
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return nil }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        guard !data.isEmpty, UIImage(data: data) != nil else { return nil }
        return data
    }

    /// Escapes Lucene reserved characters per
    /// https://lucene.apache.org/core/2_9_4/queryparsersyntax.html#Escaping%20Special%20Characters
    /// so titles/artists with `:` `(` etc. don't break the query.
    nonisolated private static func luceneEscape(_ s: String) -> String {
        let reserved: Set<Character> = ["+", "-", "&", "|", "!", "(", ")", "{", "}", "[", "]", "^", "\"", "~", "*", "?", ":", "\\", "/"]
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            if reserved.contains(ch) {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }
}

/// Serializes calls to MusicBrainz to honor their 1 req/sec limit. Lives in an
/// actor so concurrent callers (e.g. two near-simultaneous track plays) queue
/// up cleanly without an unbounded sleep storm.
actor MusicBrainzRateLimiter {
    private var nextAllowed: Date = .distantPast
    private let minimumInterval: TimeInterval = 1.05

    func waitTurn() async {
        let now = Date()
        if now < nextAllowed {
            let delay = nextAllowed.timeIntervalSince(now)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        nextAllowed = Date().addingTimeInterval(minimumInterval)
    }
}
