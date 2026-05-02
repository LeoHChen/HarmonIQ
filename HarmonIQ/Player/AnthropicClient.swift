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

    static var isConfigured: Bool { apiKey != nil }

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

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: AnthropicClient.apiKeyDefaultsKey) }
    }

    init() {
        self.apiKey = UserDefaults.standard.string(forKey: AnthropicClient.apiKeyDefaultsKey) ?? ""
    }

    var isConfigured: Bool { !apiKey.isEmpty }
}
