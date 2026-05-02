import SwiftUI

/// Clock icon that opens the sleep-timer picker. Works in both the skinned player
/// top bar and the SwiftUI NowPlayingView transport row.
///
/// Uses confirmationDialog instead of Menu to avoid the _UIReparentingView crash
/// that SwiftUI's Menu triggers when it is hosted inside a sheet.
struct SleepTimerButton: View {
    @EnvironmentObject var player: AudioPlayerManager
    @State private var showDialog = false

    var body: some View {
        Button {
            showDialog = true
        } label: {
            Image(systemName: "moon.zzz.fill")
                .font(.title2)
                .foregroundStyle(isActive ? Color.accentColor : .white.opacity(0.85),
                                 .black.opacity(0.6))
        }
        .accessibilityLabel(isActive ? "Sleep timer active" : "Set sleep timer")
        .confirmationDialog("Sleep Timer", isPresented: $showDialog, titleVisibility: .visible) {
            Button("15 minutes") { player.setSleepTimer(minutes: 15) }
            Button("30 minutes") { player.setSleepTimer(minutes: 30) }
            Button("45 minutes") { player.setSleepTimer(minutes: 45) }
            Button("60 minutes") { player.setSleepTimer(minutes: 60) }
            Button("End of current track") { player.setSleepTimerEndOfTrack() }
            if isActive {
                Button("Cancel timer", role: .destructive) { player.cancelSleepTimer() }
            }
        }
    }

    private var isActive: Bool {
        player.sleepTimerEndsAt != nil || player.sleepStopAtTrackEnd
    }
}

/// Shows a small LCD-style countdown when a sleep timer is running.
/// Zero-height when no timer is active so layout stays clean.
struct SleepTimerCountdown: View {
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        Group {
            if player.sleepStopAtTrackEnd {
                label(text: "SLEEP: END OF TRACK")
            } else if let endsAt = player.sleepTimerEndsAt {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let remaining = max(0, endsAt.timeIntervalSinceNow)
                    label(text: "SLEEP: \(formatRemaining(remaining))")
                }
            }
        }
    }

    @ViewBuilder
    private func label(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 11))
                .foregroundStyle(WinampTheme.lcdGlow)
            Text(text)
                .font(WinampTheme.lcdFont(size: 11))
                .foregroundStyle(WinampTheme.lcdGlow)
        }
        .lcdReadout(corner: 3)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
