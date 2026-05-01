import SwiftUI

/// Clock icon that opens the sleep-timer menu. Works in both the skinned player
/// top bar and the SwiftUI NowPlayingView transport row.
struct SleepTimerButton: View {
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        Menu {
            Button("15 minutes") { player.setSleepTimer(minutes: 15) }
            Button("30 minutes") { player.setSleepTimer(minutes: 30) }
            Button("45 minutes") { player.setSleepTimer(minutes: 45) }
            Button("60 minutes") { player.setSleepTimer(minutes: 60) }
            Divider()
            Button("End of current track") { player.setSleepTimerEndOfTrack() }
            if player.sleepTimerEndsAt != nil || player.sleepStopAtTrackEnd {
                Divider()
                Button("Cancel timer", role: .destructive) { player.cancelSleepTimer() }
            }
        } label: {
            Image(systemName: timerIconName)
                .font(.title2)
                .foregroundStyle(isActive ? Color.accentColor : .white.opacity(0.85),
                                 .black.opacity(0.6))
        }
        .accessibilityLabel(isActive ? "Sleep timer active" : "Set sleep timer")
    }

    private var isActive: Bool {
        player.sleepTimerEndsAt != nil || player.sleepStopAtTrackEnd
    }

    private var timerIconName: String {
        isActive ? "timer" : "timer"
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
            Image(systemName: "timer")
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
