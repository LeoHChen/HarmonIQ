import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var seekingValue: Double?

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            ArtworkView(track: player.currentTrack, size: 280, cornerRadius: 18)
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 12)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text(player.currentTrack?.displayTitle ?? "—")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(player.currentTrack?.displayArtist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let album = player.currentTrack?.displayAlbum {
                    Text(album).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { seekingValue ?? player.currentTime },
                        set: { seekingValue = $0 }
                    ),
                    in: 0...max(player.duration, 0.01),
                    onEditingChanged: { editing in
                        if !editing, let v = seekingValue {
                            player.seek(to: v)
                            seekingValue = nil
                        }
                    }
                )
                .tint(.accentColor)

                HStack {
                    Text(formatDuration(seekingValue ?? player.currentTime))
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Text("-" + formatDuration(max(player.duration - (seekingValue ?? player.currentTime), 0)))
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            HStack(spacing: 36) {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .font(.title3)
                        .foregroundStyle(player.isShuffleEnabled ? Color.accentColor : Color.secondary)
                }
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.title)
                }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title)
                }
                Button { player.cycleRepeatMode() } label: {
                    Image(systemName: repeatIconName)
                        .font(.title3)
                        .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
                }
            }
            .foregroundStyle(.primary)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal)
        .background(
            LinearGradient(colors: [Color(.systemBackground), Color.accentColor.opacity(0.08)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private var repeatIconName: String {
        switch player.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(track: player.currentTrack, size: 44, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.displayTitle ?? "—").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(player.currentTrack?.displayArtist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.title3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Color.secondary.opacity(0.3)), alignment: .top)
    }
}
