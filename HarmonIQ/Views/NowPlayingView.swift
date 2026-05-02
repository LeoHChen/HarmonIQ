import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var skinManager: SkinManager
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var seekingValue: Double?
    @State private var showSkinPicker = false
    // Save AI-curated queue as a playlist (issue #58).
    @State private var showSavePrompt = false
    @State private var savePlaylistName = ""
    @State private var saveToast: String?
    @State private var saveToastUntil = Date.distantPast

    var body: some View {
        ZStack {
            WinampTheme.appBackground.ignoresSafeArea()

            VStack(spacing: 18) {
                // Skin picker + grab handle. Without the skin picker here,
                // selecting "None (SwiftUI player)" left no way to switch
                // back to a skinned player from the now-playing screen.
                HStack {
                    // Tap cycles to the next skin; long-press opens a
                    // scrollable picker. Same affordance as the skinned
                    // player so behavior is consistent across both views.
                    Button {
                        skinManager.cycleToNextSkin()
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .font(.title3)
                            .foregroundStyle(WinampTheme.lcdGlow.opacity(0.85))
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                            showSkinPicker = true
                        }
                    )
                    .accessibilityLabel("Cycle to next skin")

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
                    FavoriteButton()
                        .environmentObject(player)
                        .environmentObject(library)
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

                    SleepTimerButton()
                        .environmentObject(player)
                }
                .padding(.top, 4)

                SleepTimerCountdown()
                    .environmentObject(player)
                    .padding(.bottom, 4)

                if let mode = player.activeSmartMode {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemImage).font(.caption)
                        Text("SMART PLAY · \(mode.title.uppercased())")
                            .font(WinampTheme.lcdFont(size: 11))
                    }
                    .lcdReadout(corner: 3)
                    .padding(.bottom, 8)
                }

                if player.aiAnnotation != nil {
                    Button {
                        savePlaylistName = defaultSaveName(annotation: player.aiAnnotation)
                        showSavePrompt = true
                    } label: {
                        Label("Save as Playlist", systemImage: "square.and.arrow.down")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(WinampTheme.lcdGlow)
                    .padding(.bottom, 8)
                }
            }
            .padding(.bottom, 24)
            .overlay(alignment: .top) { saveToastView }
        }
        .sheet(isPresented: $showSkinPicker) {
            SkinPickerSheet()
                .environmentObject(skinManager)
        }
        .alert("Save Smart Play Queue", isPresented: $showSavePrompt) {
            TextField("Name", text: $savePlaylistName)
            Button("Save") {
                let trimmed = savePlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                performSave(name: trimmed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current AI-curated queue as a regular playlist on the drive that owns most of the tracks.")
        }
        .onAppear  { player.setVisualizerActive(true)  }
        .onDisappear { player.setVisualizerActive(false) }
    }

    @ViewBuilder
    private var saveToastView: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
            let remaining = saveToastUntil.timeIntervalSince(timeline.date)
            if remaining > 0, let msg = saveToast {
                Text(msg)
                    .font(WinampTheme.lcdFont(size: 12))
                    .foregroundStyle(WinampTheme.lcdGlow)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WinampTheme.lcdBackground.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(WinampTheme.lcdGlow.opacity(0.6)))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 60)
                    .opacity(min(1.0, remaining / 0.4))
                    .transition(.opacity)
            }
        }
    }

    private func performSave(name: String) {
        guard let annotation = player.aiAnnotation else { return }
        let queueIDs = player.queue.map { $0.stableID }
        let result = library.saveSmartPlaylist(
            name: name,
            trackIDs: queueIDs,
            prompt: annotation.prompt,
            mode: annotation.mode
        )
        if let result = result {
            saveToast = result.partial
                ? "Saved \(result.savedCount) of \(result.totalCount) tracks"
                : "Saved \(result.savedCount) tracks"
        } else {
            saveToast = "Couldn't save — no drive contains the queue"
        }
        saveToastUntil = Date().addingTimeInterval(2.0)
    }

    private func defaultSaveName(annotation: AIQueueAnnotation?) -> String {
        if let prompt = annotation?.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            // Capitalize first character; truncate to ~40 chars.
            let titled = prompt.prefix(1).uppercased() + prompt.dropFirst()
            return String(titled.prefix(40))
        }
        if let title = annotation?.title, !title.isEmpty {
            return String(title.prefix(40))
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "Smart Mix — \(df.string(from: Date()))"
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

/// Heart toggle for the currently playing track. Reflects favorite state via
/// `library.isFavorite(_:)` and writes through `library.toggleFavorite(_:)`,
/// which auto-creates the drive's Favorites playlist on first toggle.
struct FavoriteButton: View {
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        let track = player.currentTrack
        let isFav = track.map { library.isFavorite($0) } ?? false
        Button {
            guard let t = track else { return }
            _ = library.toggleFavorite(t)
        } label: {
            Image(systemName: isFav ? "heart.fill" : "heart")
                .font(.title2)
                .foregroundStyle(isFav ? WinampTheme.lcdGlow : WinampTheme.lcdDim)
        }
        .chromeButton(pressed: isFav)
        .disabled(track == nil)
        .accessibilityLabel(isFav ? "Unfavorite track" : "Favorite track")
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
