import SwiftUI

struct SmartPlayView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager
    @StateObject private var aiSettings = AnthropicSettings.shared
    @State private var vibeMatchPrompt: String = ""
    @State private var showVibePrompt = false
    @State private var aiError: String?

    private var ruleBasedModes: [SmartPlayMode] { SmartPlayMode.allCases.filter { !$0.requiresAI } }
    private var aiModes: [SmartPlayMode] { SmartPlayMode.allCases.filter { $0.requiresAI } }

    var body: some View {
        Group {
            if library.tracks.isEmpty {
                EmptyStateView(title: "Nothing to play yet",
                               message: "Index a music drive first, then come back for Smart Play.",
                               systemImage: "wand.and.stars")
            } else {
                List {
                    Section {
                        Text("Pick a vibe — HarmonIQ will build the queue for you.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        ForEach(ruleBasedModes) { mode in
                            SmartPlayRow(mode: mode, pool: library.tracks, onTap: { play(mode: $0) })
                        }
                    }
                    Section {
                        ForEach(aiModes) { mode in
                            SmartPlayRow(mode: mode,
                                         pool: library.tracks,
                                         disabled: !aiSettings.isConfigured,
                                         onTap: { play(mode: $0) })
                        }
                        if !aiSettings.isConfigured {
                            NavigationLink {
                                AISettingsView()
                            } label: {
                                Label("Add Anthropic API key in Settings", systemImage: "key")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }
                        }
                    } header: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("AI-CURATED")
                        }
                    } footer: {
                        if let curating = player.aiCurating {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Claude is curating \(curating.title)…")
                                    .font(.caption)
                            }
                        } else if let annotation = player.aiAnnotation {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(annotation.title).font(.caption.bold())
                                Text(annotation.blurb).font(.caption)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Smart Play")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Vibe Match", isPresented: $showVibePrompt) {
            TextField("rainy afternoon, pre-workout hype, …", text: $vibeMatchPrompt)
            Button("Curate") {
                runAI(mode: .vibeMatch, prompt: vibeMatchPrompt)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type a free-text vibe. Claude will pick tracks from your library that match.")
        }
        .alert("Curation failed", isPresented: Binding(
            get: { aiError != nil },
            set: { if !$0 { aiError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aiError ?? "")
        }
    }

    private func play(mode: SmartPlayMode) {
        if mode == .vibeMatch {
            vibeMatchPrompt = ""
            showVibePrompt = true
            return
        }
        if mode.requiresAI {
            runAI(mode: mode, prompt: "")
            return
        }
        player.playSmart(mode: mode, from: library.tracks)
    }

    private func runAI(mode: SmartPlayMode, prompt: String) {
        Task {
            do {
                try await player.playSmartAI(mode: mode, from: library.tracks, userPrompt: prompt)
            } catch {
                aiError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private struct SmartPlayRow: View {
    let mode: SmartPlayMode
    let pool: [Track]
    var disabled: Bool = false
    let onTap: (SmartPlayMode) -> Void
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        Button {
            onTap(mode)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                    Image(systemName: mode.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(mode.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(disabled ? Color.secondary : Color.primary)
                        Spacer()
                        if player.activeSmartMode == mode {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        } else if player.aiCurating == mode {
                            ProgressView().controlSize(.small)
                        }
                    }
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    if let count = matchCount {
                        Text("\(count) tracks")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// For modes that filter on duration, show a quick count so users know the pool isn't empty.
    private var matchCount: Int? {
        switch mode {
        case .quickHits: return pool.filter { $0.duration > 0 && $0.duration < 180 }.count
        case .longPlayer: return pool.filter { $0.duration >= 360 }.count
        default: return nil
        }
    }
}
