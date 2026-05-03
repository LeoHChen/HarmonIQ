import Foundation
import Combine
import CryptoKit
import Network
import UIKit

/// Opt-in online artist-photo fetcher (issue #93).
///
/// Sibling to `ArtworkFetcher`. Looks up an artist's MusicBrainz ID, then
/// resolves the Wikidata entity's `P18` image (a Wikimedia Commons file) and
/// writes the result to
/// `<DriveRoot>/HarmonIQ/Artwork/artists/<sha1(artistName)>.jpg`, with the
/// same security-scoped bookmark dance album art uses. The local sandbox
/// gets a mirrored copy so views can read images without holding scope.
///
/// Privacy: like `ArtworkFetcher`, this is off by default. The toggle in
/// Settings is separate from the album-art toggle so users can opt into one
/// and not the other. When off, every public entry point is a no-op — no
/// network traffic of any kind.
///
/// Reuse: this fetcher *shares* the `MusicBrainzRateLimiter` instance owned
/// by `ArtworkFetcher.shared` so artist + album lookups can't burst-hit
/// MusicBrainz collectively. The Wikidata + Wikimedia Commons hops are not
/// rate-limited beyond polite back-off; both are CDN-fronted and tolerate
/// modest concurrency, but we still serialize the bulk refresh through the
/// same rate-limited gate to keep the per-IP profile predictable.
///
/// Threading mirrors `ArtworkFetcher`: `@MainActor` for published progress
/// and writes to `LibraryStore`; network + IO hop to detached tasks.
@MainActor
final class ArtistPhotoFetcher: ObservableObject {
    static let shared = ArtistPhotoFetcher()

    // MARK: - User preference

    private static let enabledDefaultsKey = "ArtistPhotoFetcher.onlineEnabled"

    /// User-visible toggle. Off by default. When false, every public entry
    /// point on this type is a no-op.
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

    /// Artist hashes (sha1 of normalized artist name) currently being
    /// fetched, so opening Artists view + a manual refresh can't issue two
    /// simultaneous network round-trips for the same artist.
    private var inFlight: Set<String> = []
    /// Artist hashes that returned no usable photo this session — either
    /// MusicBrainz had no MBID, the MBID had no Wikidata link, or the
    /// Wikidata entity had no `P18`. Cleared on relaunch so an upstream
    /// correction lets the next session retry.
    private var negativeCache: Set<String> = []

    // MARK: - Reachability

    private let pathMonitor = NWPathMonitor()
    private var pathMonitorStarted = false
    private var lastKnownPath: NWPath?

    // MARK: - Rate limiter (shared)

    /// Shares `ArtworkFetcher`'s rate limiter so artist + album lookups
    /// can't burst-hit MusicBrainz collectively.
    private let rateLimiter: MusicBrainzRateLimiter

    private init() {
        self.isOnlineFetchEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        self.rateLimiter = ArtworkFetcher.shared.musicBrainzRateLimiter
    }

    // MARK: - Reachability gate

    private func isOnline() -> Bool {
        if !pathMonitorStarted {
            pathMonitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor [weak self] in
                    self?.lastKnownPath = path
                }
            }
            pathMonitor.start(queue: DispatchQueue(label: "net.leochen.harmoniq.artistphoto.path"))
            pathMonitorStarted = true
            // Same optimistic-on-cold-start behavior as ArtworkFetcher.
            return true
        }
        guard let path = lastKnownPath else { return true }
        return path.status == .satisfied
    }

    // MARK: - Public API

    /// Fire-and-forget: if no local photo exists for this artist, queue a
    /// fetch attempt. Safe to call from view code — never blocks. Caller
    /// supplies `rootBookmarkID` so we know where to persist the JPEG.
    func fetchIfMissing(artist: String, rootBookmarkID: UUID) {
        guard isOnlineFetchEnabled else { return }
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.lowercased() != "unknown",
              trimmed.caseInsensitiveCompare(LibraryStore.variousArtistsLabel) != .orderedSame
        else { return }

        let hash = Self.sha1Hex(trimmed)

        // Already have local photo for this artist → nothing to do.
        let localTarget = LibraryStore.shared.artistPhotoDirectory.appendingPathComponent("\(hash).jpg")
        if FileManager.default.fileExists(atPath: localTarget.path) { return }

        if negativeCache.contains(hash) { return }
        if inFlight.contains(hash) { return }

        if !isOnline() { return }

        inFlight.insert(hash)
        Task.detached(priority: .utility) { [weak self] in
            await self?.runFetch(artistHash: hash,
                                 artist: trimmed,
                                 rootBookmarkID: rootBookmarkID)
        }
    }

    /// Bulk pass over a drive: walks every artist that lacks a photo and
    /// tries to fill it. Serialized through the shared MusicBrainz rate
    /// limiter so we never exceed 1 req/sec.
    func refreshMissingArtistPhotos(for root: LibraryRoot) {
        guard isOnlineFetchEnabled else { return }
        guard !isRefreshing else { return }

        let rootID = root.id
        let allTracks = LibraryStore.shared.tracks.filter { $0.rootBookmarkID == rootID }
        var seenArtists: Set<String> = []
        var queue: [(hash: String, artist: String)] = []
        let localCache = LibraryStore.shared.artistPhotoDirectory
        for t in allTracks {
            let artist = t.displayArtist
            if seenArtists.contains(artist) { continue }
            seenArtists.insert(artist)
            let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.lowercased() == "unknown" { continue }
            if trimmed.caseInsensitiveCompare(LibraryStore.variousArtistsLabel) == .orderedSame { continue }
            let hash = Self.sha1Hex(trimmed)
            let local = localCache.appendingPathComponent("\(hash).jpg")
            if FileManager.default.fileExists(atPath: local.path) { continue }
            if negativeCache.contains(hash) { continue }
            queue.append((hash, trimmed))
        }

        if queue.isEmpty {
            refreshStatusMessage = "No artists missing photos on \(root.displayName)."
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
        refreshStatusMessage = "Fetching photos for \(queue.count) artists…"

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

    nonisolated private func runFetch(artistHash: String,
                                      artist: String,
                                      rootBookmarkID: UUID) async {
        defer {
            Task { @MainActor [weak self] in
                self?.inFlight.remove(artistHash)
            }
        }
        let result = await Self.lookupAndDownload(artist: artist, rateLimiter: rateLimiter)
        guard let imageData = result else {
            await MainActor.run {
                _ = self.negativeCache.insert(artistHash)
            }
            return
        }
        await MainActor.run {
            self.persistDownloadedPhoto(imageData,
                                        artistHash: artistHash,
                                        rootBookmarkID: rootBookmarkID)
        }
    }

    nonisolated private func runBulkRefresh(queue: [(hash: String, artist: String)],
                                            rootBookmarkID: UUID,
                                            rootName: String) async {
        var succeeded = 0
        var processed = 0
        for entry in queue {
            if Task.isCancelled { break }
            let result = await Self.lookupAndDownload(artist: entry.artist, rateLimiter: rateLimiter)
            processed += 1
            if let data = result {
                succeeded += 1
                let localProcessed = processed
                let localSucceeded = succeeded
                let localTotal = queue.count
                await MainActor.run {
                    self.persistDownloadedPhoto(data,
                                                artistHash: entry.hash,
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

    /// Writes the downloaded image to the drive's `HarmonIQ/Artwork/artists/`
    /// folder (or the local cache for read-only roots), mirrors locally so
    /// future renders don't hold scope, and bumps `LibraryStore`'s artist
    /// snapshot so the Artists grid invalidates its representative-image
    /// cache and re-renders.
    private func persistDownloadedPhoto(_ data: Data,
                                        artistHash: String,
                                        rootBookmarkID: UUID) {
        guard let root = LibraryStore.shared.roots.first(where: { $0.id == rootBookmarkID }) else { return }
        let localCache = LibraryStore.shared.artistPhotoDirectory

        let savedFilename: String?
        if root.isReadOnly {
            // Read-only roots store all artwork in the sandbox.
            savedFilename = MetadataExtractor.saveArtwork(data, named: artistHash, to: localCache)
        } else {
            do {
                let driveSaved: String? = try BookmarkStore.withAccess(to: root.bookmark) { driveURL in
                    let driveArt = DriveLibraryStore.artistArtworkFolder(in: driveURL)
                    try? FileManager.default.createDirectory(at: driveArt, withIntermediateDirectories: true)
                    let written = MetadataExtractor.saveArtwork(data, named: artistHash, to: driveArt)
                    if written != nil {
                        let src = driveArt.appendingPathComponent("\(artistHash).jpg")
                        let dst = localCache.appendingPathComponent("\(artistHash).jpg")
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

        guard savedFilename != nil else { return }

        // Bump the artist-photo snapshot so any cached representative-image
        // pick (which prefers a real photo over an album cover) recomputes.
        LibraryStore.shared.invalidateArtistRepresentativeCache()
    }

    // MARK: - Helpers (static / nonisolated)

    nonisolated static func sha1Hex(_ s: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// User-Agent string per MusicBrainz etiquette.
    nonisolated static func userAgent() -> String {
        "HarmonIQ/\(BuildInfo.version) (https://github.com/LeoHChen/HarmonIQ)"
    }

    // MARK: - MusicBrainz → Wikidata → Wikimedia Commons

    /// Per-process cache of MBID → Wikidata image filename ("Foo.jpg") so a
    /// repeat lookup of the same artist within a session avoids the second
    /// hop. Negative entries (no MBID, no P18) are tracked via the parent
    /// `negativeCache` keyed by artist hash.
    private actor LookupCache {
        private var mbidToImage: [String: String] = [:]
        func record(mbid: String, image: String) { mbidToImage[mbid] = image }
        func image(forMBID mbid: String) -> String? { mbidToImage[mbid] }
    }
    nonisolated private static let lookupCache = LookupCache()

    /// Returns image bytes on success, nil on any failure.
    nonisolated private static func lookupAndDownload(artist: String,
                                                      rateLimiter: MusicBrainzRateLimiter) async -> Data? {
        // 1) MusicBrainz artist search — get MBID.
        await rateLimiter.waitTurn()
        guard let mbid = await searchArtistMBID(artist: artist) else { return nil }

        // 2) Resolve the Wikidata image filename. Per-process cache so a
        //    repeat lookup of the same MBID (different runs of the bulk
        //    pass, or two near-simultaneous fetches from view + Settings)
        //    skips the round-trip.
        let imageFilename: String
        if let cached = await lookupCache.image(forMBID: mbid) {
            imageFilename = cached
        } else {
            await rateLimiter.waitTurn()
            guard let resolved = await resolveWikidataImage(mbid: mbid) else { return nil }
            await lookupCache.record(mbid: mbid, image: resolved)
            imageFilename = resolved
        }

        // 3) Download the actual image bytes from Wikimedia Commons.
        return await downloadCommonsImage(filename: imageFilename)
    }

    /// Searches MusicBrainz for an artist by name and returns the
    /// highest-scoring MBID. Documented limitation: when MusicBrainz has
    /// multiple matching artists with the same name we pick the top hit
    /// without disambiguation.
    nonisolated private static func searchArtistMBID(artist: String) async -> String? {
        let escaped = luceneEscape(artist)
        let query = "artist:\"\(escaped)\""
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/artist/")
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
        guard let artists = json["artists"] as? [[String: Any]] else { return nil }

        // Prefer exact name match → high score; otherwise top-scoring entry.
        let lowered = artist.lowercased()
        let candidates = artists.compactMap { a -> (id: String, score: Int, nameMatch: Bool)? in
            guard let id = a["id"] as? String else { return nil }
            let score = (a["score"] as? Int) ?? 0
            let name = (a["name"] as? String)?.lowercased() ?? ""
            return (id, score, name == lowered)
        }
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.nameMatch != rhs.nameMatch { return lhs.nameMatch }
            return lhs.score > rhs.score
        }
        return sorted.first?.id
    }

    /// Looks up the Wikidata entity ID linked to `mbid` via the MusicBrainz
    /// `url-rels`, then queries Wikidata for property `P18` (image) on that
    /// entity. Returns the bare filename (e.g. `"Some Artist.jpg"`).
    nonisolated private static func resolveWikidataImage(mbid: String) async -> String? {
        // 3a) MusicBrainz artist with url-rels — look for a Wikidata link.
        guard let mbURL = URL(string: "https://musicbrainz.org/ws/2/artist/\(mbid)?inc=url-rels&fmt=json") else {
            return nil
        }
        var mbReq = URLRequest(url: mbURL)
        mbReq.timeoutInterval = 10
        mbReq.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        mbReq.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (mbData, mbResp) = try? await URLSession.shared.data(for: mbReq) else { return nil }
        guard let mbHTTP = mbResp as? HTTPURLResponse, (200..<300).contains(mbHTTP.statusCode) else {
            return nil
        }
        guard let mbJSON = try? JSONSerialization.jsonObject(with: mbData) as? [String: Any] else { return nil }
        let rels = (mbJSON["relations"] as? [[String: Any]]) ?? []
        var wikidataID: String?
        for rel in rels {
            // Both `type` == "wikidata" and a target URL on wikidata.org work.
            let type = (rel["type"] as? String)?.lowercased() ?? ""
            let urlObj = rel["url"] as? [String: Any]
            let resource = (urlObj?["resource"] as? String) ?? ""
            if type == "wikidata" || resource.contains("wikidata.org/wiki/Q") {
                if let q = resource.split(separator: "/").last.map(String.init), q.hasPrefix("Q") {
                    wikidataID = q
                    break
                }
            }
        }
        guard let qid = wikidataID else { return nil }

        // 3b) Wikidata: fetch the entity, pull P18.
        guard let wdURL = URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(qid).json") else {
            return nil
        }
        var wdReq = URLRequest(url: wdURL)
        wdReq.timeoutInterval = 10
        wdReq.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        wdReq.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (wdData, wdResp) = try? await URLSession.shared.data(for: wdReq) else { return nil }
        guard let wdHTTP = wdResp as? HTTPURLResponse, (200..<300).contains(wdHTTP.statusCode) else {
            return nil
        }
        guard let wdJSON = try? JSONSerialization.jsonObject(with: wdData) as? [String: Any],
              let entities = wdJSON["entities"] as? [String: Any],
              let entity = entities[qid] as? [String: Any],
              let claims = entity["claims"] as? [String: Any],
              let p18 = claims["P18"] as? [[String: Any]],
              let firstClaim = p18.first,
              let mainsnak = firstClaim["mainsnak"] as? [String: Any],
              let datavalue = mainsnak["datavalue"] as? [String: Any],
              let value = datavalue["value"] as? String,
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Wikimedia Commons direct-image URL via the `Special:FilePath`
    /// redirect (resolves to upload.wikimedia.org). We ask for a 600px
    /// thumbnail to match what `MetadataExtractor.saveArtwork` re-encodes
    /// into anyway.
    nonisolated private static func downloadCommonsImage(filename: String) async -> Data? {
        // Spaces are converted to underscores by MediaWiki, but Special:FilePath
        // accepts either form; URLComponents handles the encoding.
        var components = URLComponents(string: "https://commons.wikimedia.org/wiki/Special:FilePath/")
        components?.path = "/wiki/Special:FilePath/" + filename
        components?.queryItems = [URLQueryItem(name: "width", value: "600")]
        guard let url = components?.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return nil }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        guard !data.isEmpty, UIImage(data: data) != nil else { return nil }
        return data
    }

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
