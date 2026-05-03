import Foundation
import Combine
import CryptoKit
import Network
import UIKit

/// Opt-in online artist-photo fetcher (issue #93, expanded by #95).
///
/// Sibling to `ArtworkFetcher`. Resolves an artist to a MusicBrainz ID, then
/// walks a fallback chain of public photo sources until one returns valid
/// image bytes:
///
///   1. **Wikidata P18** via the MBID's `url-rels` → Wikimedia Commons.
///   2. **TheAudioDB** `artist-mb.php?i=<MBID>` → `strArtistThumb`.
///      (Test key `2`; documented public-use mirror, no user key required.)
///   3. **Wikipedia REST summary** thumbnail. Page title is derived from the
///      MBID's `url-rels` Wikipedia URL when present, else best-effort by
///      artist name. The Wikipedia summary endpoint is permissive about CORS
///      but expects a User-Agent — we send the same string MusicBrainz wants.
///
/// Fanart.tv is intentionally **not** in the chain. Their `webservice/v3`
/// endpoint requires a per-app API key and we don't ship credentials; the
/// "personal-API-key public mirror" alluded to by the issue brief turned out
/// not to be a stable keyless path. TheAudioDB + Wikipedia together cover
/// most of what Fanart.tv would have added.
///
/// First valid bytes win. The winning source is recorded per-MBID purely
/// for diagnostics — the on-disk file at
/// `<DriveRoot>/HarmonIQ/Artwork/artists/<sha1>.jpg` is the real cache, and
/// `fetchIfMissing` short-circuits on its presence before the chain even
/// starts.
///
/// Privacy: still gated by the single "Fetch artist photos online" toggle.
/// Off by default; when off every public entry point is a no-op. The
/// Settings footer copy lists every source so the user knows what's queried.
///
/// Rate limits: MusicBrainz hops continue to share the
/// `MusicBrainzRateLimiter` owned by `ArtworkFetcher.shared` (1 req/sec
/// across album + artist lookups). Other hosts (TheAudioDB, Wikipedia,
/// Wikimedia Commons) get their own per-host actors with the same
/// 1-req-sec floor so concurrent artist lookups don't burst on any single
/// host. Different hosts can be hit in parallel within one artist's lookup.
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
    /// Artist hashes that returned no usable photo this session — every
    /// source in the fallback chain came back empty (no MBID, no Wikidata
    /// link / `P18`, no TheAudioDB thumb, no Wikipedia summary thumbnail).
    /// Cleared on relaunch so an upstream correction lets the next session
    /// retry.
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

    // MARK: - Photo source chain

    /// Which source produced the bytes we ended up writing. Recorded
    /// per-MBID for diagnostics — handy when triaging "why does this
    /// artist's photo look weird?" against the chain order.
    enum PhotoSource: String {
        case wikidataP18
        case theAudioDB
        case wikipediaSummary
    }

    /// Per-process MBID → winning source record. Survives only for the
    /// lifetime of the process — relaunches re-walk the chain so upstream
    /// corrections are picked up. Successful lookups are persisted to disk
    /// so this in-memory map only matters within a single session;
    /// repeated calls within a session normally short-circuit on
    /// "file already exists" before reaching the chain.
    private actor LookupCache {
        private var sourceByMBID: [String: PhotoSource] = [:]
        func record(mbid: String, source: PhotoSource) { sourceByMBID[mbid] = source }
    }
    nonisolated private static let lookupCache = LookupCache()

    /// Per-host rate gates for the non-MusicBrainz sources. Same 1-req/sec
    /// floor MusicBrainz asks for — TheAudioDB and Wikipedia are far more
    /// permissive in practice, but a uniform floor keeps the per-IP profile
    /// predictable and avoids surprises if upstream tightens. The Commons
    /// gate also covers Wikipedia thumbnail hosts (both resolve to
    /// `upload.wikimedia.org`). Different hosts can be hit in parallel
    /// within one artist lookup since each gate is a separate actor.
    nonisolated private static let theAudioDBGate = MusicBrainzRateLimiter()
    nonisolated private static let wikipediaGate = MusicBrainzRateLimiter()
    nonisolated private static let commonsGate = MusicBrainzRateLimiter()

    /// Returns image bytes on success, nil if every source in the chain
    /// failed. Sources are tried in order; the first valid bytes win.
    nonisolated private static func lookupAndDownload(artist: String,
                                                      rateLimiter: MusicBrainzRateLimiter) async -> Data? {
        // 1) MusicBrainz artist search — get MBID. No MBID → no chain.
        await rateLimiter.waitTurn()
        guard let mbid = await searchArtistMBID(artist: artist) else { return nil }

        // 2) Fetch the MB artist's url-rels once and reuse it for both
        //    Wikidata + Wikipedia derivations. Saves a round-trip.
        await rateLimiter.waitTurn()
        let rels = await fetchMBUrlRels(mbid: mbid)

        // 3) Wikidata P18 — historically the highest-quality source.
        if let qid = wikidataQID(fromRels: rels) {
            if let data = await fetchWikidataP18(qid: qid) {
                await lookupCache.record(mbid: mbid, source: .wikidataP18)
                return data
            }
        }

        // 4) TheAudioDB strArtistThumb. Keyless (test key `2`, documented
        //    for public use). Often has portraits when MB has no Wikidata.
        if let data = await fetchTheAudioDB(mbid: mbid) {
            await lookupCache.record(mbid: mbid, source: .theAudioDB)
            return data
        }

        // 5) Wikipedia REST summary thumbnail. Title preference: explicit
        //    `wikipedia` url-rel from MB, then bare artist name. Documented
        //    failure modes: artists with no Wikipedia article, articles
        //    with no `thumbnail.source` field, disambiguation pages, and
        //    name collisions when we fall back to artist-name lookup.
        if let data = await fetchWikipediaSummary(rels: rels, artistFallback: artist) {
            await lookupCache.record(mbid: mbid, source: .wikipediaSummary)
            return data
        }

        return nil
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

    // MARK: - MusicBrainz url-rels (shared by Wikidata + Wikipedia paths)

    /// Fetches the MusicBrainz artist record with `inc=url-rels` and returns
    /// the raw `relations` array. Empty array on any failure — callers
    /// should treat that as "no usable rels found" and fall through.
    nonisolated private static func fetchMBUrlRels(mbid: String) async -> [[String: Any]] {
        guard let url = URL(string: "https://musicbrainz.org/ws/2/artist/\(mbid)?inc=url-rels&fmt=json") else {
            return []
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return [] }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return (json["relations"] as? [[String: Any]]) ?? []
    }

    /// Extracts the Wikidata entity ID (`Q####`) from a MusicBrainz rels
    /// array, if a wikidata url-rel is present.
    nonisolated private static func wikidataQID(fromRels rels: [[String: Any]]) -> String? {
        for rel in rels {
            let type = (rel["type"] as? String)?.lowercased() ?? ""
            let urlObj = rel["url"] as? [String: Any]
            let resource = (urlObj?["resource"] as? String) ?? ""
            if type == "wikidata" || resource.contains("wikidata.org/wiki/Q") {
                if let q = resource.split(separator: "/").last.map(String.init), q.hasPrefix("Q") {
                    return q
                }
            }
        }
        return nil
    }

    /// Extracts the Wikipedia article title from a MusicBrainz rels array,
    /// preferring English Wikipedia. The MB `wikipedia` rel resource looks
    /// like `https://en.wikipedia.org/wiki/Some_Artist`. Returns the bare
    /// title (still URL-encoded if the resource was encoded) so the caller
    /// can plug it into the REST summary endpoint. Nil if no wikipedia
    /// rel exists.
    ///
    /// Documented failure mode: an artist with only a non-English Wikipedia
    /// rel will return nil here, and we fall through to artist-name lookup
    /// against `en.wikipedia.org` — a deliberate bias toward the English
    /// summary corpus, since that's what Wikipedia's REST API serves
    /// reliably without a per-language base URL.
    nonisolated private static func wikipediaTitle(fromRels rels: [[String: Any]]) -> String? {
        var fallbackTitle: String?
        for rel in rels {
            let type = (rel["type"] as? String)?.lowercased() ?? ""
            guard type == "wikipedia" else { continue }
            let urlObj = rel["url"] as? [String: Any]
            let resource = (urlObj?["resource"] as? String) ?? ""
            // Match `https://<lang>.wikipedia.org/wiki/<Title>`.
            guard let url = URL(string: resource),
                  let host = url.host,
                  host.hasSuffix(".wikipedia.org"),
                  url.pathComponents.count >= 3,
                  url.pathComponents[1] == "wiki"
            else { continue }
            let title = url.pathComponents[2]
            if host == "en.wikipedia.org" {
                return title
            } else if fallbackTitle == nil {
                fallbackTitle = title
            }
        }
        return fallbackTitle
    }

    // MARK: - Source 1: Wikidata P18

    /// Resolves Wikidata `P18` for `qid` and downloads the Commons image.
    /// Returns image bytes or nil.
    nonisolated private static func fetchWikidataP18(qid: String) async -> Data? {
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
        return await downloadCommonsImage(filename: value)
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

        await commonsGate.waitTurn()

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

    // MARK: - Source 2: TheAudioDB

    /// Looks up an artist by MBID on TheAudioDB and downloads
    /// `strArtistThumb` (or `strArtistFanart` as a secondary). The `2` test
    /// API key is documented for non-commercial public use; if upstream
    /// changes that policy this source goes silent and the chain falls
    /// through to Wikipedia.
    ///
    /// Returns image bytes or nil.
    nonisolated private static func fetchTheAudioDB(mbid: String) async -> Data? {
        await theAudioDBGate.waitTurn()
        guard let url = URL(string: "https://www.theaudiodb.com/api/v1/json/2/artist-mb.php?i=\(mbid)") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // TheAudioDB returns `{ "artists": null }` for unknown MBIDs and
        // `{ "artists": [ {...} ] }` for known ones.
        guard let artists = json["artists"] as? [[String: Any]], let first = artists.first else {
            return nil
        }
        let candidateKeys = ["strArtistThumb", "strArtistFanart", "strArtistFanart2", "strArtistFanart3"]
        for key in candidateKeys {
            if let value = first[key] as? String, !value.isEmpty,
               let imageURL = URL(string: value) {
                if let bytes = await downloadImage(from: imageURL, gate: nil) {
                    return bytes
                }
            }
        }
        return nil
    }

    // MARK: - Source 3: Wikipedia REST summary thumbnail

    /// Hits Wikipedia's `page/summary` endpoint for the best title we can
    /// derive (MB `wikipedia` rel preferred, else artist-name fallback) and
    /// returns the JSON `thumbnail.source` image bytes.
    ///
    /// Failure modes worth noting for future debugging:
    ///   * No Wikipedia article → 404 → nil.
    ///   * Article is a disambiguation page → summary returns no
    ///     `thumbnail` → nil. We don't try to disambiguate further; that's
    ///     a separate quality-of-search problem and out of scope per #95.
    ///   * Article exists but has no lead image → no thumbnail → nil.
    ///   * Non-English Wikipedia rel → falls through to en.wikipedia.org
    ///     name lookup, which can hit the wrong article for ambiguous
    ///     names. Acceptable failure mode given the chain order — by this
    ///     point Wikidata + TheAudioDB have already failed.
    nonisolated private static func fetchWikipediaSummary(rels: [[String: Any]],
                                                          artistFallback: String) async -> Data? {
        let title: String
        if let fromRels = wikipediaTitle(fromRels: rels) {
            title = fromRels
        } else {
            // Best-effort: use the artist name as the page title. MediaWiki
            // accepts spaces or underscores; URLComponents handles encoding.
            let trimmed = artistFallback.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            title = trimmed.replacingOccurrences(of: " ", with: "_")
        }

        var components = URLComponents(string: "https://en.wikipedia.org/api/rest_v1/page/summary/")
        components?.path = "/api/rest_v1/page/summary/" + title
        guard let url = components?.url else { return nil }

        await wikipediaGate.waitTurn()
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Skip disambiguation pages — `type == "disambiguation"`.
        if let type = json["type"] as? String, type == "disambiguation" { return nil }
        // `originalimage` (full size) preferred; `thumbnail` is the 320px
        // scaled crop. Either is fine, since we re-encode at 600px anyway.
        let imageDicts = [json["originalimage"] as? [String: Any],
                          json["thumbnail"] as? [String: Any]]
        for dict in imageDicts {
            if let dict, let source = dict["source"] as? String, let imageURL = URL(string: source) {
                // Wikipedia thumbs live on upload.wikimedia.org, same as
                // Commons — share the gate.
                if let bytes = await downloadImage(from: imageURL, gate: commonsGate) {
                    return bytes
                }
            }
        }
        return nil
    }

    // MARK: - Generic image download

    /// Downloads bytes from `url` and verifies they decode as an image.
    /// Optional `gate` lets the caller serialize against a per-host limiter.
    nonisolated private static func downloadImage(from url: URL,
                                                  gate: MusicBrainzRateLimiter?) async -> Data? {
        if let gate { await gate.waitTurn() }
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
