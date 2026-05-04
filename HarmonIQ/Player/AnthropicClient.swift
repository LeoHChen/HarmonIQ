import Foundation

/// Minimal async client for the Anthropic Messages API. Used by the AI
/// Smart Play modes (Vibe Match, Storyteller, Sonic Contrast — issue #25).
///
/// Stays small on purpose: no SDK dep, no streaming, no tool use, no
/// retries. The user provides their own API key via Settings; the key is
/// stored in UserDefaults (not the Keychain — this is a personal-library
/// app and the user already trusts the device with their own key).
enum AnthropicClient {
    /// Default model for Smart Play curation calls. Haiku 4.5 keeps the
    /// round-trip latency low — track-list selection from a manifest is
    /// well within Haiku's strengths and the user is waiting on a
    /// progress spinner.
    static let defaultModel = "claude-haiku-4-5-20251001"

    /// UserDefaults key for the user-supplied Anthropic API key.
    static let apiKeyDefaultsKey = "harmoniq.anthropic.apiKey"

    static var apiKey: String? {
        let v = UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? ""
        return v.isEmpty ? nil : v
    }

    /// True when the user has entered an Anthropic API key. Read directly
    /// from UserDefaults so the gating helper (`AIProvider.anyAvailable`)
    /// can stay non-isolated.
    static var hasKey: Bool { apiKey != nil }

    static var isConfigured: Bool { hasKey }

    enum ClientError: Error, LocalizedError {
        case missingAPIKey
        case httpError(Int, String)
        case decodeError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add your Anthropic API key in Settings → AI to use this mode."
            case .httpError(let code, let body):
                return "Anthropic API error \(code): \(body)"
            case .decodeError(let detail):
                return "Couldn't read the model's response: \(detail)"
            }
        }
    }

    /// Send a single-turn prompt and return the assistant's plain-text
    /// response. The system prompt is marked as cacheable (5 min TTL) so
    /// repeated curations within a session are cheaper.
    static func send(systemPrompt: String,
                     userPrompt: String,
                     model: String = defaultModel,
                     maxTokens: Int = 4096) async throws -> String {
        guard let key = apiKey else { throw ClientError.missingAPIKey }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Prompt-caching beta header — system prompts get a 5 min TTL.
        req.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [
                ["type": "text", "text": systemPrompt, "cache_control": ["type": "ephemeral"]],
            ],
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ClientError.httpError(-1, "no response")
        }
        if http.statusCode >= 400 {
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            throw ClientError.httpError(http.statusCode, bodyStr)
        }

        // Parse the response shape: { content: [ { type: "text", text: "..." }, ... ] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw ClientError.decodeError("unexpected envelope")
        }
        let text = content.compactMap { $0["text"] as? String }.joined()
        if text.isEmpty {
            throw ClientError.decodeError("empty content")
        }
        return text
    }
}

/// UserDefaults-backed configuration for the AI features. Exposed as a
/// small ObservableObject so the Settings UI binds cleanly.
@MainActor
final class AnthropicSettings: ObservableObject {
    static let shared = AnthropicSettings()
    static let useAppleIntelligenceKey = "harmoniq.ai.useAppleIntelligence"

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: AnthropicClient.apiKeyDefaultsKey) }
    }

    /// When true (and Apple Intelligence is available), AI Smart Play
    /// routes through the on-device Foundation Models session instead of
    /// the Anthropic API. No key needed, no network egress.
    @Published var useAppleIntelligence: Bool {
        didSet { UserDefaults.standard.set(useAppleIntelligence, forKey: Self.useAppleIntelligenceKey) }
    }

    init() {
        self.apiKey = UserDefaults.standard.string(forKey: AnthropicClient.apiKeyDefaultsKey) ?? ""
        // Default ON when the user hasn't expressed a preference — local
        // is strictly better when it's available (free + private). AI
        // rows fall back to the Anthropic key if Apple Intelligence
        // rejects at runtime.
        self.useAppleIntelligence = (UserDefaults.standard.object(forKey: Self.useAppleIntelligenceKey) as? Bool) ?? true
    }

    /// True when at least one AI backend is usable right now — either
    /// Apple Intelligence (preferred when toggled on) or a configured
    /// Anthropic key.
    var isConfigured: Bool {
        if useAppleIntelligence && AppleIntelligenceClient.isAvailable { return true }
        return !apiKey.isEmpty
    }
}

/// Single source of truth for "is any AI backend usable on this device?".
/// `SmartPlayView` and `AISettingsView` gate UI on `anyAvailable` so AI
/// affordances disappear entirely on devices that can run neither
/// Apple Intelligence nor the cloud client (e.g. iPhone 14 with no
/// Anthropic key) instead of greying out.
enum AIProvider {
    /// True when at least one provider can accept a curation call right
    /// now: Apple Intelligence on-device is reachable, OR the user has
    /// stored an Anthropic API key. The toggle preference doesn't matter
    /// here — `SmartPlayAI.pickBackend` falls through to cloud when local
    /// is off, so a configured key alone is enough to expose AI rows.
    static var anyAvailable: Bool {
        AppleIntelligenceClient.isAvailable || AnthropicClient.hasKey
    }
}
