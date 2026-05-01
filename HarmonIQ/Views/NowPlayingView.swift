import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.dismiss) private var dismiss
    @State private var seekingValue: Double?

    var body: some View {
        ZStack {
            WinampTheme.appBackground.ignoresSafeArea()

            VStack(spacing: 18) {
                // Skin picker + grab handle. Without the skin picker here,
                // selecting "None (SwiftUI player)" left no way to switch
                // back to a skinned player from the now-playing screen.
                HStack {
                    Menu {
                        Button {
                            skinManager.clearSkin()
                        } label: {
                            Label("None (SwiftUI player)",
                                  systemImage: skinManager.activeSkin == nil ? "checkmark" : "circle")
                        }
                        Divider()
                        ForEach(skinManager.skins) { skin in
                            Button {
                                skinManager.selectSkin(skin)
                            } label: {
                                Label(skin.displayName,
                                      systemImage: skinManager.activeSkin?.id == skin.id ? "checkmark" : "circle")
                            }
                        }
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .font(.title3)
                            .foregroundStyle(WinampTheme.lcdGlow.opacity(0.85))
                    }
                    .accessibilityLabel("Switch skin")

                    Spacer()

                    Capsule()
                        .fill(WinampTheme.bevelLight.opacity(0.25))
                        .frame(width: 40, height: 5)

                    Spacer()

                    // Symmetric spacer so the capsule stays centered.
                    Image(systemName: "paintpalette.fill")
                        .font(.title3)
                        .opacity(0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // LCD readout strip — title scroll + bitrate-style stats
                VStack(spacing: 4) {
                    Text(player.currentTrack?.displayTitle.uppercased() ?? "NO SIGNAL")
                        .font(WinampTheme.lcdFont(size: 18))
                        .lineLimit(1)
                    Text(player.currentTrack?.displayArtist.uppercased() ?? "—")
                        .font(WinampTheme.lcdFont(size: 12))
                        .foregroundStyle(WinampTheme.lcdDim)
                        .lineLimit(1)
                    HStack {
                        Text(formatDuration(seekingValue ?? player.currentTime))
                            .font(WinampTheme.lcdFont(size: 12))
                        Spacer()
                        Text("\(formatBitrate(player.currentTrack))  \(formatRate(player.currentTrack))")
                            .font(WinampTheme.lcdFont(size: 11))
                            .foregroundStyle(WinampTheme.lcdDim)
                        Spacer()
                        Text("-" + formatDuration(max(player.duration - (seekingValue ?? player.currentTime), 0)))
                            .font(WinampTheme.lcdFont(size: 12))
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .lcdReadout()
                .padding(.horizontal, 16)

                // Artwork + small now-playing chip
                HStack(spacing: 12) {
                    ArtworkView(track: player.currentTrack, size: 96, cornerRadius: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(WinampTheme.bevelLight.opacity(0.4), lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 6) {
                        Text((player.currentTrack?.displayAlbum ?? "—").uppercased())
                            .font(WinampTheme.lcdFont(size: 11))
                            .foregroundStyle(WinampTheme.lcdDim)
                            .lineLimit(2)
                        if let year = player.currentTrack?.year {
                            Text("\(String(year))")
                                .font(WinampTheme.lcdFont(size: 11))
                                .foregroundStyle(WinampTheme.lcdDim)
                        }
                        Spacer()
                        Text("CH \(player.queue.isEmpty ? 0 : player.currentIndex + 1)/\(player.queue.count)")
                            .font(WinampTheme.lcdFont(size: 11))
                            .foregroundStyle(WinampTheme.lcdGlow)
                    }
                    Spacer()
                }
                .bevelPanel()
                .padding(.horizontal, 16)

                // Visualizer panel — fills the rest of the vertical space
                VisualizerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 220)
                    .padding(.horizontal, 16)

                // Seek bar
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
                    .tint(WinampTheme.lcdGlow)
                }
                .padding(10)
                .bevelPanel()
                .padding(.horizontal, 16)

                // Transport controls
                HStack(spacing: 14) {
                    Button { player.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .font(.title3)
                    }
                    .chromeButton(pressed: player.isShuffleEnabled)

                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill").font(.title3)
                    }
                    .chromeButton()

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .frame(width: 44, height: 30)
                    }
                    .chromeButton()

                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.title3)
                    }
                    .chromeButton()

                    Button { player.cycleRepeatMode() } label: {
                        Image(systemName: repeatIconName)
                            .font(.title3)
                    }
                    .chromeButton(pressed: player.repeatMode != .off)
                }
                .padding(.top, 4)

                if let mode = player.activeSmartMode {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemImage).font(.caption)
                        Text("SMART PLAY · \(mode.title.uppercased())")
                            .font(WinampTheme.lcdFont(size: 11))
                    }
                    .lcdReadout(corner: 3)
                    .padding(.bottom, 8)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var repeatIconName: String {
        switch player.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func formatBitrate(_ track: Track?) -> String {
        guard let track = track, track.fileSize > 0, track.duration > 0 else { return "---kbps" }
        let kbps = Int((Double(track.fileSize) * 8 / 1000) / track.duration)
        return "\(kbps)kbps"
    }

    private func formatRate(_ track: Track?) -> String {
        guard let format = track?.fileFormat else { return "" }
        return format.uppercased()
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(track: player.currentTrack, size: 38, cornerRadius: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(WinampTheme.bevelLight.opacity(0.4), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.displayTitle.uppercased() ?? "—")
                    .font(WinampTheme.lcdFont(size: 12))
                    .foregroundStyle(WinampTheme.lcdGlow)
                    .lineLimit(1)
                Text(player.currentTrack?.displayArtist.uppercased() ?? "")
                    .font(WinampTheme.lcdFont(size: 10))
                    .foregroundStyle(WinampTheme.lcdDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            EQVisualizer(isAnimating: player.isPlaying)
                .frame(width: 44, height: 22)

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body)
            }
            .chromeButton()

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
            }
            .chromeButton()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(WinampTheme.panelGradient)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(WinampTheme.bevelLight.opacity(0.5)),
                 alignment: .top)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(WinampTheme.bevelDark),
                 alignment: .bottom)
    }
}
