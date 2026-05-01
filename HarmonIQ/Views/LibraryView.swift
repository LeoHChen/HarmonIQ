import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        ZStack {
            WinampTheme.appBackground.ignoresSafeArea()

            List {
                Section {
                    NavigationLink {
                        SmartPlayView()
                    } label: {
                        WinampNavRow(title: "SMART PLAY", icon: "wand.and.stars", isFeatured: true)
                    }
                } header: {
                    SectionHeader("// FOR YOU")
                } footer: {
                    Text("Curated queues built from your library — random, by artist, by genre, by decade, and more.")
                        .font(WinampTheme.lcdFont(size: 10))
                        .foregroundStyle(WinampTheme.lcdDim)
                }
                .listRowBackground(Color.clear)

                Section {
                    NavigationLink {
                        AllTracksView()
                    } label: {
                        WinampNavRow(title: "ALL TRACKS", icon: "music.note", count: library.tracks.count)
                    }
                    NavigationLink {
                        ArtistsView()
                    } label: {
                        WinampNavRow(title: "ARTISTS", icon: "music.mic", count: library.allArtists.count)
                    }
                    NavigationLink {
                        AlbumsView()
                    } label: {
                        WinampNavRow(title: "ALBUMS", icon: "square.stack", count: library.allAlbums.count)
                    }
                    NavigationLink {
                        FoldersView()
                    } label: {
                        WinampNavRow(title: "FOLDERS", icon: "folder", count: library.roots.count)
                    }
                    if let track = player.currentTrack {
                        Button {
                            player.presentNowPlaying()
                        } label: {
                            WinampNowPlayingRow(track: track, isPlaying: player.isPlaying, levels: player.levels)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    SectionHeader("// BROWSE")
                }
                .listRowBackground(Color.clear)

                if library.tracks.isEmpty {
                    Section {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            WinampNavRow(title: "ADD A MUSIC DRIVE", icon: "externaldrive.badge.plus", isFeatured: true)
                        }
                    } footer: {
                        Text("Pick a folder from the Files app — including external USB drives — to index your music collection.")
                            .font(WinampTheme.lcdFont(size: 10))
                            .foregroundStyle(WinampTheme.lcdDim)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("HARMONIQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(WinampTheme.lcdFont(size: 11))
            .foregroundStyle(WinampTheme.lcdDim)
            .padding(.top, 6)
    }
}

struct WinampNowPlayingRow: View {
    let track: Track
    let isPlaying: Bool
    let levels: SIMD2<Float>

    /// Smoothed envelope so the glow eases instead of strobing on every meter
    /// tick. Decays slowly (kept at 30Hz from AudioPlayerManager).
    @State private var envelope: Float = 0

    var body: some View {
        // Smooth peak with a fast attack / slow release so the glow tracks the
        // beat without flickering. Pause freezes the envelope at zero.
        let target = isPlaying ? max(levels.x, levels.y * 0.85) : 0
        let glow = CGFloat(envelope)

        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(WinampTheme.lcdBackground)
                RoundedRectangle(cornerRadius: 3)
                    .fill(WinampTheme.lcdGlow.opacity(0.18 + 0.55 * glow))
                Image(systemName: isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WinampTheme.lcdGlow)
                    .scaleEffect(1.0 + 0.18 * glow)
            }
            .frame(width: 28, height: 28)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(WinampTheme.lcdGlow.opacity(0.6)))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .shadow(color: WinampTheme.lcdGlow.opacity(0.35 + 0.55 * glow),
                    radius: 2 + 8 * glow)

            VStack(alignment: .leading, spacing: 2) {
                Text("PLAYER")
                    .font(WinampTheme.lcdFont(size: 13))
                    .foregroundStyle(WinampTheme.lcdGlow)
                Text(track.displayTitle.uppercased())
                    .font(WinampTheme.lcdFont(size: 10))
                    .foregroundStyle(WinampTheme.lcdDim)
                    .lineLimit(1)
            }

            Spacer()

            BeatBars(intensity: glow, isPlaying: isPlaying)
                .frame(width: 22, height: 18)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WinampTheme.lcdDim)
        }
        .contentShape(Rectangle())
        .onChange(of: levels) { _ in
            // Fast attack so the bass kick feels live.
            let next = target
            envelope = max(envelope * 0.78, next)
        }
        .onChange(of: isPlaying) { playing in
            if !playing {
                withAnimation(.easeOut(duration: 0.25)) { envelope = 0 }
            }
        }
    }
}

/// Three-bar mini-VU that breathes on the playing track. Pure decoration, but
/// it sells the "this row is alive" feel the user asked for.
private struct BeatBars: View {
    let intensity: CGFloat
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                bar(phase: t * 7.3, base: 0.35)
                bar(phase: t * 5.1 + 1.7, base: 0.55)
                bar(phase: t * 9.7 + 0.4, base: 0.45)
            }
        }
    }

    @ViewBuilder
    private func bar(phase: Double, base: CGFloat) -> some View {
        // Wobble each bar at its own phase so they feel independent. Multiply
        // by the live envelope so paused/quiet sections settle to a low idle.
        let wobble = (sin(phase) + 1) * 0.5
        let height: CGFloat = max(2, (base + 0.5 * intensity) * (0.4 + 0.6 * CGFloat(wobble)) * 18)
        RoundedRectangle(cornerRadius: 1)
            .fill(WinampTheme.lcdGlow.opacity(0.5 + 0.5 * intensity))
            .frame(width: 4, height: height)
            .shadow(color: WinampTheme.lcdGlow.opacity(0.4 * intensity), radius: 2 * intensity)
    }
}

struct WinampNavRow: View {
    let title: String
    let icon: String
    var count: Int? = nil
    var isFeatured: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isFeatured ? WinampTheme.lcdGlow : WinampTheme.lcdDim)
                .frame(width: 28, height: 28)
                .background(WinampTheme.lcdBackground)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(WinampTheme.bevelDark))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: isFeatured ? WinampTheme.lcdGlow.opacity(0.4) : .clear, radius: 2)

            Text(title)
                .font(WinampTheme.lcdFont(size: 13))
                .foregroundStyle(isFeatured ? WinampTheme.lcdGlow : Color(red: 0.85, green: 0.92, blue: 0.85))

            Spacer()

            if let count = count {
                Text("\(count)")
                    .font(WinampTheme.lcdFont(size: 11))
                    .foregroundStyle(WinampTheme.lcdGlow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WinampTheme.lcdBackground)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(WinampTheme.bevelDark))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }
}
