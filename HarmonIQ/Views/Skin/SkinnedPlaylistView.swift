import SwiftUI

/// Winamp-style playlist editor: shows the current play queue as a tight,
/// monospaced list. The currently playing row is highlighted; tapping a row
/// jumps playback to that track.
struct SkinnedPlaylistView: View {
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("PLAYLIST EDITOR")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(WinampTheme.lcdGlow)
                    .padding(.horizontal, 8)
                Spacer()
                Text("\(player.queue.count) tracks")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(WinampTheme.lcdDim)
                    .padding(.horizontal, 8)
            }
            .padding(.vertical, 4)
            .background(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.10)], startPoint: .top, endPoint: .bottom))

            if player.queue.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(player.queue.enumerated()), id: \.offset) { idx, track in
                                row(idx: idx, track: track)
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
        .background(Color.black)
        .overlay(
            Rectangle().stroke(Color(white: 0.25), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("Queue is empty")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(WinampTheme.lcdDim)
            Text("Pick a track from the Library tab to start playback.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(idx: Int, track: Track) -> some View {
        let isCurrent = idx == player.currentIndex
        return Button {
            player.play(track: track, in: player.queue)
        } label: {
            HStack(spacing: 8) {
                Text(String(format: "%2d.", idx + 1))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isCurrent ? WinampTheme.lcdGlow : WinampTheme.lcdDim)
                    .frame(width: 28, alignment: .trailing)
                Text("\(track.displayArtist) – \(track.displayTitle)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isCurrent ? WinampTheme.lcdGlow : Color(white: 0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(formatDuration(track.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isCurrent ? WinampTheme.lcdGlow : WinampTheme.lcdDim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isCurrent ? Color(white: 0.12) : Color.clear)
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
