import SwiftUI

/// Winamp-style playlist editor: shows the current play queue as a tight,
/// monospaced list. The currently playing row is highlighted; tapping a row
/// jumps playback to that track. Colors track the active skin's PLEDIT.TXT
/// palette (normal text, current track text, selected background); falls
/// back to WinampTheme defaults when no skin is active.
struct SkinnedPlaylistView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var skinManager: SkinManager

    var body: some View {
        let palette = SkinPalette(skin: skinManager.activeSkin)

        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("PLAYLIST EDITOR")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.current)
                    .padding(.horizontal, 8)
                Spacer()
                Text("\(player.queue.count) tracks")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.normal.opacity(0.7))
                    .padding(.horizontal, 8)
            }
            .padding(.vertical, 4)
            .background(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.10)], startPoint: .top, endPoint: .bottom))

            if player.queue.isEmpty {
                emptyState(palette: palette)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(player.queue.enumerated()), id: \.offset) { idx, track in
                                row(idx: idx, track: track, palette: palette)
                                    .id(idx)
                            }
                        }
                    }
                    .onChange(of: player.currentIndex) { new in
                        withAnimation { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
        }
        .background(palette.background)
        .overlay(
            Rectangle().stroke(Color(white: 0.25), lineWidth: 1)
        )
    }

    private func emptyState(palette: SkinPalette) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text("Queue is empty")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.normal.opacity(0.7))
            Text("Pick a track from the Library tab to start playback.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(idx: Int, track: Track, palette: SkinPalette) -> some View {
        let isCurrent = idx == player.currentIndex
        let textColor = isCurrent ? palette.current : palette.normal
        return Button {
            player.play(track: track, in: player.queue)
        } label: {
            HStack(spacing: 8) {
                Text(String(format: "%2d.", idx + 1))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(textColor.opacity(isCurrent ? 1 : 0.75))
                    .frame(width: 28, alignment: .trailing)
                Text("\(track.displayArtist) – \(track.displayTitle)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(formatDuration(track.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(textColor.opacity(isCurrent ? 1 : 0.75))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isCurrent ? palette.selectedBackground : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Resolves the active skin's PLEDIT.TXT palette into SwiftUI Colors with sensible
/// fallbacks for the no-skin (None) case so panels stay readable in either mode.
struct SkinPalette {
    let normal: Color
    let current: Color
    let background: Color
    let selectedBackground: Color

    init(skin: WinampSkin?) {
        if let s = skin {
            self.normal = Color(uiColor: s.playlistColors.normal)
            self.current = Color(uiColor: s.playlistColors.current)
            self.background = Color(uiColor: s.playlistColors.normalBG)
            self.selectedBackground = Color(uiColor: s.playlistColors.selectedBG)
        } else {
            self.normal = Color(white: 0.85)
            self.current = WinampTheme.lcdGlow
            self.background = Color.black
            self.selectedBackground = Color(white: 0.12)
        }
    }
}
