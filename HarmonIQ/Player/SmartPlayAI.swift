import Foundation

/// AI-driven Smart Play curation. Three modes per issue #25:
///   - Vibe Match: free-text user prompt → curated queue + per-track rationales
///   - Storyteller: model picks a thematic 8–12 track narrative arc
///   - Sonic Contrast: alternates between stylistically different tracks
///
/// Two backends share this pipeline:
///   - Anthropic (cloud): generous context, full stableIDs in the manifest.
///   - Apple Intelligence (on-device): 4096-token window, so we send a
///     much smaller manifest with positional indexes and slim metadata.
///     The smaller manifest is also random-sampled so any subset of the
///     library can be the starting pool.
enum SmartPlayAI {
    /// What the model returns + a sortable view of the library it saw.
    struct Curated {
        let title: String
        let blurb: String
        let trackIDs: [String]
        /// Per-track one-liner rationale, keyed by stableID.
        let rationales: [String: String]
    }

    /// Maximum tracks we send to the cloud backend. Cloud has plenty of
    /// context; this caps token cost on huge libraries.
    static let cloudManifestCap = 1000

    /// Maximum tracks we send to the on-device backend. Apple Intelligence's
    /// foundation model has a 4096-token context window — system prompt +
    /// user-prompt scaffolding + the model's response all live in that
    /// budget too. With slim metadata + positional indexes (instead of
    /// 40-char SHA1 stableIDs) this is the largest manifest that fits
    /// reliably with room for a 25-track response.
    static let onDeviceManifestCap = 60

    static func curate(mode: SmartPlayMode, userPrompt: String, pool: [Track]) async throws -> Curated {
        // Pick the backend up-front so we can size the manifest correctly.
        let backend = await pickBackend()

        // Sample the pool. On-device gets a random sample (any subset of
        // the library can seed a session); cloud gets the front of the
        // library (cheap and good enough at 1000 entries).
        let sampled: [Track]
        switch backend {
        case .appleIntelligence:
            sampled = randomSample(pool: pool, count: onDeviceManifestCap)
        case .anthropic:
            sampled = Array(pool.prefix(cloudManifestCap))
        }

        let systemPrompt = systemPrompt(for: mode, backend: backend)
        let userText: String
        switch backend {
        case .appleIntelligence:
            // Index-based ids (`"0"`, `"1"`, …) save ~40 chars per row vs
            // SHA1 stableIDs — critical for the 4K window.
            let manifest = slimManifest(pool: sampled)
            userText = """
            \(userPromptPreamble(for: mode, userText: userPrompt))

            Library (\(manifest.count) tracks; id is the row's index):
            \(jsonString(manifest))

            Return ONLY a JSON object — no markdown fences, no commentary:
            {"title":"…","blurb":"…","queue":[{"id":"<index>","why":"…"}]}
            """
        case .anthropic:
            let manifest = fullManifest(pool: sampled)
            userText = """
            \(userPromptPreamble(for: mode, userText: userPrompt))

            Library (\(manifest.count) tracks):
            \(jsonString(manifest))

            Return ONLY a JSON object with this shape (no markdown fence, no commentary):
            {
              "title": "<short queue title>",
              "blurb": "<one short paragraph framing the queue>",
              "queue": [
                {"id": "<stableID from the library>", "why": "<one sentence rationale>"}
              ]
            }
            """
        }

        let raw: String
        switch backend {
        case .appleIntelligence:
            raw = try await AppleIntelligenceClient.send(systemPrompt: systemPrompt, userPrompt: userText)
        case .anthropic:
            raw = try await AnthropicClient.send(systemPrompt: systemPrompt, userPrompt: userText)
        }
        return try parse(raw: raw, backend: backend, sampledPool: sampled)
    }

    enum Backend { case appleIntelligence, anthropic }

    @MainActor
    private static func pickBackend() -> Backend {
        let s = AnthropicSettings.shared
        if s.useAppleIntelligence && AppleIntelligenceClient.isAvailable {
            return .appleIntelligence
        }
        return .anthropic
    }

    // MARK: - Prompt construction

    private static func systemPrompt(for mode: SmartPlayMode, backend: Backend) -> String {
        let idGuidance: String
        switch backend {
        case .appleIntelligence:
            idGuidance = "- The `id` value in your output must be the row's numeric index from the manifest (string form), nothing else."
        case .anthropic:
            idGuidance = "- The `id` value must be the exact stableID string from the manifest. Never invent IDs."
        }
        let baseline = """
        You are an expert music curator embedded in HarmonIQ, a personal
        music player. The user gives you their music library as a compact
        JSON manifest, plus a curation goal. Your job is to pick an
        ordered queue (a subset of the manifest) and give a one-sentence
        rationale per track.

        Hard constraints:
        \(idGuidance)
        - Output is JSON only, with the exact shape specified by the user.
        - Keep `blurb` under 280 characters.
        - Aim for 12-25 tracks unless the goal asks for fewer.
        - Order matters — sequence is part of the curation.
        """

        switch mode {
        case .vibeMatch:
            return baseline + "\n\nVibe Match: pick tracks that match the mood the user describes; rationales explain *why* each one fits."
        case .storyteller:
            return baseline + "\n\nStoryteller: build a narrative arc — a beginning, a peak, a resolution. The blurb names the arc; rationales explain each track's role in it."
        case .sonicContrast:
            return baseline + "\n\nSonic Contrast: alternate between stylistically different tracks (genre, energy, era) so adjacent tracks feel intentionally distinct. Rationales describe the contrast pivot."
        default:
            return baseline
        }
    }

    private static func userPromptPreamble(for mode: SmartPlayMode, userText: String) -> String {
        switch mode {
        case .vibeMatch:
            let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Goal: pick a vibe at random and run with it."
                : "Vibe prompt from the user: \(trimmed)"
        case .storyteller:
            return "Goal: assemble a thematic mini-album — 8 to 12 tracks that tell one story."
        case .sonicContrast:
            return "Goal: build a queue where adjacent tracks contrast sharply in style."
        default:
            return "Goal: pick a curated queue."
        }
    }

    // MARK: - Manifests

    /// Full manifest entry — used for the cloud backend.
    private struct FullManifestEntry: Encodable {
        let id: String
        let title: String
        let artist: String
        let album: String
        let year: Int?
        let genre: String?
        let durationSec: Int
    }

    /// Slim manifest entry — used for the on-device backend. Drops album +
    /// duration and uses a positional index as id, halving the per-row
    /// token cost.
    private struct SlimManifestEntry: Encodable {
        let id: String     // positional index ("0", "1", …)
        let title: String
        let artist: String
        let year: Int?
        let genre: String?
    }

    private static func fullManifest(pool: [Track]) -> [FullManifestEntry] {
        pool.map { t in
            FullManifestEntry(
                id: t.stableID,
                title: t.displayTitle,
                artist: t.displayArtist,
                album: t.displayAlbum,
                year: t.year,
                genre: t.genre?.nilIfBlank,
                durationSec: Int(t.duration.rounded())
            )
        }
    }

    private static func slimManifest(pool: [Track]) -> [SlimManifestEntry] {
        pool.enumerated().map { (idx, t) in
            SlimManifestEntry(
                id: String(idx),
                title: t.displayTitle,
                artist: t.displayArtist,
                year: t.year,
                genre: t.genre?.nilIfBlank
            )
        }
    }

    private static func randomSample(pool: [Track], count: Int) -> [Track] {
        guard pool.count > count else { return pool.shuffled() }
        return Array(pool.shuffled().prefix(count))
    }

    private static func jsonString<T: Encodable>(_ value: T) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys] // deterministic for caching
        guard let data = try? enc.encode(value),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    // MARK: - Parsing

    private static func parse(raw: String, backend: Backend, sampledPool: [Track]) throws -> Curated {
        // Models occasionally wrap JSON in fences despite explicit "no markdown" — strip.
        let trimmed = stripCodeFence(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        // On-device output sometimes contains stray prose around the JSON
        // even with explicit instructions; pull out the first {...} block.
        let jsonText = extractFirstJSONObject(trimmed) ?? trimmed
        guard let data = jsonText.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnthropicClient.ClientError.decodeError("not JSON: \(raw.prefix(200))")
        }
        let title = (obj["title"] as? String) ?? "Smart Mix"
        let blurb = (obj["blurb"] as? String) ?? ""
        guard let queue = obj["queue"] as? [[String: Any]] else {
            throw AnthropicClient.ClientError.decodeError("missing `queue` array")
        }
        var trackIDs: [String] = []
        var rationales: [String: String] = [:]
        for entry in queue {
            guard let rawId = entry["id"] else { continue }
            // The model occasionally returns an integer instead of a string
            // — accept either.
            let idStr: String
            if let s = rawId as? String { idStr = s }
            else if let n = rawId as? Int { idStr = String(n) }
            else { continue }
            // Map back to a stableID. On-device path sent positional
            // indexes, so resolve through the sampled pool.
            let resolved: String?
            switch backend {
            case .appleIntelligence:
                if let i = Int(idStr), i >= 0, i < sampledPool.count {
                    resolved = sampledPool[i].stableID
                } else {
                    resolved = nil
                }
            case .anthropic:
                resolved = idStr
            }
            guard let stableID = resolved else { continue }
            trackIDs.append(stableID)
            if let why = entry["why"] as? String { rationales[stableID] = why }
        }
        return Curated(title: title, blurb: blurb, trackIDs: trackIDs, rationales: rationales)
    }

    private static func stripCodeFence(_ s: String) -> String {
        guard s.hasPrefix("```") else { return s }
        var rest = s.dropFirst(3)
        if let nl = rest.firstIndex(of: "\n") { rest = rest[rest.index(after: nl)...] }
        if let close = rest.range(of: "```", options: .backwards) {
            rest = rest[..<close.lowerBound]
        }
        return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Find the first balanced `{...}` substring. Used to forgive stray
    /// prose the on-device model sometimes inserts around the JSON.
    private static func extractFirstJSONObject(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        var idx = start
        while idx < s.endIndex {
            let c = s[idx]
            if escape { escape = false; idx = s.index(after: idx); continue }
            if inString {
                if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
            } else {
                if c == "\"" { inString = true }
                else if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(s[start...idx])
                    }
                }
            }
            idx = s.index(after: idx)
        }
        return nil
    }
}
