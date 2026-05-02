import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device curator backed by Apple Intelligence's Foundation Models
/// framework (iOS 26+). When available, AI Smart Play (issue #25) can
/// run entirely on-device with no API key and no network egress.
///
/// Falls back to a clear `unavailable` error on:
/// - iOS < 26 (framework not present),
/// - device doesn't support Apple Intelligence (e.g. iPhone 14 or older),
/// - user hasn't enabled Apple Intelligence in Settings.
enum AppleIntelligenceClient {
    enum AvailabilityState {
        case available
        case requiresOSUpdate          // OS lacks the framework
        case deviceNotEligible         // iPhone 14 or older, etc.
        case appleIntelligenceDisabled // user-toggle off in Settings
        case modelNotReady             // assets still downloading
        case unknown(String)
    }

    enum ClientError: Error, LocalizedError {
        case unavailable(AvailabilityState)
        case decodeError(String)
        case sessionError(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let s):
                switch s {
                case .available:
                    return "Apple Intelligence is available."
                case .requiresOSUpdate:
                    return "Apple Intelligence requires iOS 26 or newer."
                case .deviceNotEligible:
                    return "This device doesn't support Apple Intelligence. Use the Anthropic API instead, or upgrade to a supported iPhone."
                case .appleIntelligenceDisabled:
                    return "Turn on Apple Intelligence in Settings → Apple Intelligence to use the on-device curator."
                case .modelNotReady:
                    return "Apple Intelligence is still downloading. Try again in a few minutes."
                case .unknown(let detail):
                    return "Apple Intelligence is unavailable: \(detail)"
                }
            case .decodeError(let detail):
                return "Couldn't read the on-device model's response: \(detail)"
            case .sessionError(let detail):
                return "On-device session failed: \(detail)"
            }
        }
    }

    /// True when Foundation Models reports the on-device LLM is ready right
    /// now. Cheap to call repeatedly.
    static var availability: AvailabilityState {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return mapSystemAvailability()
        } else {
            return .requiresOSUpdate
        }
        #else
        return .requiresOSUpdate
        #endif
    }

    static var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    /// Send a single-turn instruction + prompt and return the assistant's
    /// plain-text response. Same signature shape as `AnthropicClient.send`
    /// so `SmartPlayAI` can dispatch on a flag without restructuring.
    static func send(systemPrompt: String, userPrompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch mapSystemAvailability() {
            case .available: break
            case let other:  throw ClientError.unavailable(other)
            }
            do {
                let session = LanguageModelSession(instructions: systemPrompt)
                let response = try await session.respond(to: userPrompt)
                return response.content
            } catch {
                throw ClientError.sessionError(String(describing: error))
            }
        } else {
            throw ClientError.unavailable(.requiresOSUpdate)
        }
        #else
        throw ClientError.unavailable(.requiresOSUpdate)
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func mapSystemAvailability() -> AvailabilityState {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceDisabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .unknown(String(describing: reason))
            }
        @unknown default:
            return .unknown("unknown availability case")
        }
    }
    #endif
}
