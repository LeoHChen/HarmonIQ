import SwiftUI

/// Settings → AI Smart Play. Lets the user pick between on-device Apple
/// Intelligence (free, private, iOS 26+) and the Anthropic Messages API
/// (works on any iOS, requires a key).
struct AISettingsView: View {
    @StateObject private var settings = AnthropicSettings.shared
    @State private var revealKey = false
    @State private var availabilityRefreshTick = 0  // forces availability re-check on appear

    private var availability: AppleIntelligenceClient.AvailabilityState {
        _ = availabilityRefreshTick
        return AppleIntelligenceClient.availability
    }

    private var availabilityLabel: String {
        switch availability {
        case .available:                  return "Available"
        case .requiresOSUpdate:           return "Requires iOS 26+"
        case .deviceNotEligible:          return "Not supported on this device"
        case .appleIntelligenceDisabled:  return "Disabled in Settings"
        case .modelNotReady:              return "Downloading…"
        case .unknown(let s):             return "Unavailable (\(s))"
        }
    }

    private var availabilityFooter: String {
        switch availability {
        case .available:
            return "On-device curation runs entirely on your iPhone — no API key, no network egress, free. Smart Play uses Apple's foundation model when this toggle is on."
        case .requiresOSUpdate:
            return "Apple Intelligence's foundation models ship with iOS 26. Update iOS or use the Anthropic API below."
        case .deviceNotEligible:
            return "Apple Intelligence requires an iPhone 15 Pro or newer. Use the Anthropic API below."
        case .appleIntelligenceDisabled:
            return "Open Settings → Apple Intelligence and enable it, then return here. The toggle is then live."
        case .modelNotReady:
            return "iOS is still downloading the Apple Intelligence model. Try again in a few minutes; the toggle will go live automatically."
        case .unknown:
            return "Apple Intelligence didn't report a known state. Falling back to the Anthropic API path."
        }
    }

    private var canEnableLocal: Bool { AppleIntelligenceClient.isAvailable }

    var body: some View {
        List {
            // Apple Intelligence (preferred when available)
            Section {
                Toggle("Use Apple Intelligence (on-device)", isOn: $settings.useAppleIntelligence)
                    .disabled(!canEnableLocal)
                LabeledContent("Status", value: availabilityLabel)
            } header: {
                Text("On-Device Curator")
            } footer: {
                Text(availabilityFooter)
            }

            // Anthropic API (used when local is off or unavailable)
            Section {
                if revealKey {
                    TextField("sk-ant-…", text: $settings.apiKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField("sk-ant-…", text: $settings.apiKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                }
                Toggle("Show key", isOn: $revealKey)
                if !settings.apiKey.isEmpty {
                    Button(role: .destructive) {
                        settings.apiKey = ""
                    } label: {
                        Label("Remove key", systemImage: "trash")
                    }
                }
            } header: {
                Text("Anthropic API Key (Cloud Fallback)")
            } footer: {
                Text("Used when Apple Intelligence is unavailable or the toggle is off. Your key is stored only on this device. Get one from console.anthropic.com — Smart Play calls run on Claude Haiku and are inexpensive.")
            }

            Section {
                LabeledContent("Active backend", value: activeBackendLabel)
                LabeledContent("Anthropic model", value: AnthropicClient.defaultModel)
            } header: {
                Text("Status")
            }

            Section {
                Text("**Vibe Match** — type a free-text vibe (e.g. ‟rainy afternoon”). The model picks tracks from your library that fit.")
                Text("**Storyteller** — assembles a thematic 8-12 track narrative arc with a short blurb at the top of the queue.")
                Text("**Sonic Contrast** — alternates between stylistically different tracks to keep the listener engaged.")
            } header: {
                Text("AI Modes")
            } footer: {
                Text("Each call sends a compact manifest of your library (title/artist/album/year/duration — no audio). With Apple Intelligence on, the manifest stays on-device.")
            }
        }
        .navigationTitle("AI Smart Play")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { availabilityRefreshTick &+= 1 }
    }

    private var activeBackendLabel: String {
        if settings.useAppleIntelligence && AppleIntelligenceClient.isAvailable {
            return "Apple Intelligence (on-device)"
        }
        return settings.apiKey.isEmpty ? "Not configured" : "Anthropic (cloud)"
    }
}
