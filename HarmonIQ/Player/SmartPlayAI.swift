import Foundation

/// AI-driven Smart Play curation. Three modes per issue #25:
///   - Vibe Match: free-text user prompt → curated queue + per-track rationales
///   - Storyteller: model picks a thematic 8–12 track narrative arc
///   - Sonic Contrast: alternates between stylistically different tracks
///
/// All three call the same Anthropic Messages endpoint with a manifest of
/// the library; the JSON response specifies which `stableID`s to play in
/// what order.
enum SmartPlayAI {
    /// What the model returns + a sortable view of the library it saw.
    struct Curated {
        let title: String
        let blurb: String
        let trackIDs: [String]
        /// Per-track one-liner rationale, keyed by stableID.
        let rationales: [String: String]
    }

    /// Maximum tracks we send in the manifest. Caps token cost on huge
    /// libraries; the model still has plenty to choose from.
    static let manifestCap = 1000

    static func curate(mode: SmartPlayMode, userPrompt: String, pool: [Track]) async throws -> Curated {
        let manifest = compactManifest(pool: pool)
        let systemPrompt = systemPrompt(for: mode)
        let userText = """
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

        // Pick the backend up-front (read MainActor state once, then drop
        // back to the actor-free pipeline). Prefer on-device when it's
        // toggled ON and the system reports the model is ready; fall back
        // to Anthropic when not.
        let backend = await pickBackend()
        let raw: String
        switch backend {
        case .appleIntelligence:
            raw = try await AppleIntelligenceClient.send(systemPrompt: systemPrompt, userPrompt: userText)
        case .anthropic:
            raw = try await AnthropicClient.send(systemPrompt: systemPrompt, userPrompt: userText)
        }
        return try parse(raw: raw)
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

    private static func systemPrompt(for mode: SmartPlayMode) -> String {
        let baseline = """
        You are an expert music curator embedded in HarmonIQ, a personal
        music player. The user gives you their full music library as a
        compact JSON manifest, plus a curation goal. Your job is to pick
        an ordered queue of `stableID`s (a subset of the manifest) and
        give a one-sentence rationale per track.

        Hard constraints:
        - Only use `stableID` values that appear in the supplied manifest.
          Never invent IDs.
        - Output is JSON only, with the exact shape specified by the user.
        - Keep `blurb` under 280 characters.
        - Aim for 12-25 tracks unless the goal explicitly asks for fewer.
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

    // MARK: - Manifest

    private struct ManifestEntry: Encodable {
        let id: String
        let title: String
        let artist: String
        let album: String
        let year: Int?
        let genre: String?
        let durationSec: Int
    }

    private static func compactManifest(pool: [Track]) -> [ManifestEntry] {
        // Cap to keep tokens low; sample the front end of the library —
        // shuffle could miss recently-indexed tracks, and slicing is
        // cheaper than a real sample for the typical case.
        let limited = pool.prefix(manifestCap)
        return limited.map { t in
            ManifestEntry(
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

    private static func jsonString<T: Encodable>(_ value: T) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys] // deterministic for caching
        guard let data = try? enc.encode(value),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    // MARK: - Parsing

    private static func parse(raw: String) throws -> Curated {
        // Models occasionally wrap JSON in fences despite explicit "no markdown" — strip.
        let trimmed = stripCodeFence(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let data = trimmed.data(using: .utf8),
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
            guard let id = entry["id"] as? String else { continue }
            trackIDs.append(id)
            if let why = entry["why"] as? String { rationales[id] = why }
        }
        return Curated(title: title, blurb: blurb, trackIDs: trackIDs, rationales: rationales)
    }

    private static func stripCodeFence(_ s: String) -> String {
        guard s.hasPrefix("```") else { return s }
        // Drop the opening fence (and an optional language tag), then find
        // the closing fence and drop it.
        var rest = s.dropFirst(3)
        if let nl = rest.firstIndex(of: "\n") { rest = rest[rest.index(after: nl)...] }
        if let close = rest.range(of: "```", options: .backwards) {
            rest = rest[..<close.lowerBound]
        }
        return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
