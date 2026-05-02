import SwiftUI

/// Settings → AI Smart Play. Captures the user's Anthropic API key and
/// shows the connection state. The key is persisted to UserDefaults.
struct AISettingsView: View {
    @StateObject private var settings = AnthropicSettings.shared
    @State private var revealKey = false

    var body: some View {
        List {
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
                Text("Anthropic API Key")
            } footer: {
                Text("Your key is stored only on this device (UserDefaults). Get a key from console.anthropic.com — small Smart Play calls run on Claude Haiku and are inexpensive.")
            }

            Section {
                LabeledContent("Status",
                               value: settings.isConfigured ? "Configured" : "Not configured")
                LabeledContent("Default model", value: AnthropicClient.defaultModel)
            } header: {
                Text("Status")
            }

            Section {
                Text("**Vibe Match** — type a free-text vibe (e.g. ‟rainy afternoon”). Claude picks tracks from your library that fit.")
                Text("**Storyteller** — Claude assembles a thematic 8-12 track narrative arc with a short blurb at the top of the queue.")
                Text("**Sonic Contrast** — alternates between stylistically different tracks to keep the listener engaged.")
            } header: {
                Text("AI Modes")
            } footer: {
                Text("Each call sends a compact manifest of your library (title/artist/album/year/duration only — no audio) to Anthropic and receives an ordered list of stableIDs back.")
            }
        }
        .navigationTitle("AI Smart Play")
        .navigationBarTitleDisplayMode(.inline)
    }
}
