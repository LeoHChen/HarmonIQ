import SwiftUI

struct SmartPlayView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager

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
                        ForEach(SmartPlayMode.allCases) { mode in
                            SmartPlayRow(mode: mode, pool: library.tracks)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Smart Play")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SmartPlayRow: View {
    let mode: SmartPlayMode
    let pool: [Track]
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        Button {
            player.playSmart(mode: mode, from: pool)
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
                            .foregroundStyle(Color.primary)
                        Spacer()
                        if player.activeSmartMode == mode {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
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
