import SwiftUI
import UIKit

struct ArtworkView: View {
    let track: Track?
    var size: CGFloat = 60
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    WinampTheme.panelGradient
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(WinampTheme.lcdGlow.opacity(0.7))
                        .shadow(color: WinampTheme.lcdGlow.opacity(0.4), radius: 2)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func loadImage() -> UIImage? {
        guard let path = track?.artworkPath else { return nil }
        let url = LibraryStore.shared.artworkDirectory.appendingPathComponent(path)
        return UIImage(contentsOfFile: url.path)
    }
}

struct TrackRow: View {
    let track: Track
    var showArtwork: Bool = true
    var showAlbum: Bool = false
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        HStack(spacing: 12) {
            if showArtwork {
                ArtworkView(track: track, size: 40, cornerRadius: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(WinampTheme.bevelLight.opacity(0.35), lineWidth: 1)
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle.uppercased())
                    .font(WinampTheme.lcdFont(size: 13))
                    .foregroundStyle(isCurrent ? WinampTheme.lcdGlow : WinampTheme.lcdText)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if showAlbum {
                        Text(track.displayAlbum.uppercased()).lineLimit(1)
                        Text("·")
                    }
                    Text(track.displayArtist.uppercased()).lineLimit(1)
                }
                .font(WinampTheme.lcdFont(size: 10))
                .foregroundStyle(WinampTheme.lcdDim)
            }
            Spacer()
            Text(formatDuration(track.duration))
                .font(WinampTheme.lcdFont(size: 11))
                .foregroundStyle(isCurrent ? WinampTheme.lcdGlow : WinampTheme.lcdDim)
        }
        .padding(.vertical, 2)
        .listRowBackground(
            isCurrent
                ? WinampTheme.lcdGlow.opacity(0.08)
                : Color.white.opacity(0.02)
        )
        .contentShape(Rectangle())
    }

    private var isCurrent: Bool {
        player.currentTrack?.stableID == track.stableID
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(WinampTheme.lcdGlow.opacity(0.7))
                .shadow(color: WinampTheme.lcdGlow.opacity(0.4), radius: 3)
            Text(title.uppercased())
                .font(WinampTheme.lcdFont(size: 14))
                .foregroundStyle(WinampTheme.lcdGlow)
            Text(message)
                .font(WinampTheme.lcdFont(size: 11))
                .foregroundStyle(WinampTheme.lcdDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
