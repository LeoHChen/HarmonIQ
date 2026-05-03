import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject var library: LibraryStore

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    var body: some View {
        Group {
            if library.allAlbums.isEmpty {
                EmptyStateView(title: "No albums",
                               message: "Index a music drive to see albums.",
                               systemImage: "square.stack")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(library.allAlbums) { key in
                            NavigationLink {
                                AlbumDetailView(key: key)
                            } label: {
                                AlbumCard(key: key)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AlbumCard: View {
    let key: LibraryStore.AlbumKey
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        let tracks = library.tracks(forAlbum: key)
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(track: tracks.first, size: 150, cornerRadius: 10)
                .frame(maxWidth: .infinity)
            Text(key.album).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(key.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct AlbumDetailView: View {
    let key: LibraryStore.AlbumKey
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        let tracks = library.tracks(forAlbum: key)
        let totalDuration = tracks.reduce(0) { $0 + $1.duration }

        List {
            Section {
                AlbumHeader(
                    key: key,
                    sample: tracks.first,
                    trackCount: tracks.count,
                    totalDuration: totalDuration,
                    onPlay: { player.playAll(tracks, startAt: 0) },
                    onShuffle: {
                        var shuffled = tracks
                        shuffled.shuffle()
                        player.isShuffleEnabled = true
                        player.playAll(shuffled, startAt: 0)
                    }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(tracks) { track in
                    TrackRow(track: track, showArtwork: false)
                        .onTapGesture {
                            player.play(track: track, in: tracks)
                        }
                        .swipeActions {
                            AddToPlaylistMenuButton(trackIDs: [track.stableID])
                        }
                }
            }
        }
        .navigationTitle(key.album)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AlbumHeader: View {
    let key: LibraryStore.AlbumKey
    let sample: Track?
    let trackCount: Int
    let totalDuration: TimeInterval
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ArtworkView(track: sample, size: 180, cornerRadius: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WinampTheme.bevelLight.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            VStack(spacing: 4) {
                Text(key.album.uppercased())
                    .font(WinampTheme.lcdFont(size: 16))
                    .foregroundStyle(WinampTheme.lcdGlow)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(key.artist.uppercased())
                    .font(WinampTheme.lcdFont(size: 12))
                    .foregroundStyle(WinampTheme.lcdText)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                Text(metaLine)
                    .font(WinampTheme.lcdFont(size: 10))
                    .foregroundStyle(WinampTheme.lcdDim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                AlbumActionButton(title: "PLAY", icon: "play.fill", isPrimary: true, action: onPlay)
                AlbumActionButton(title: "SHUFFLE", icon: "shuffle", isPrimary: false, action: onShuffle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let year = sample?.year { parts.append(String(year)) }
        parts.append("\(trackCount) TRACK\(trackCount == 1 ? "" : "S")")
        parts.append(formatDuration(totalDuration).uppercased())
        return parts.joined(separator: " · ")
    }
}

private struct AlbumActionButton: View {
    let title: String
    let icon: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(WinampTheme.lcdFont(size: 12))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isPrimary ? WinampTheme.lcdGlow : WinampTheme.lcdText)
            .background(WinampTheme.lcdBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isPrimary ? WinampTheme.lcdGlow.opacity(0.6) : WinampTheme.bevelDark, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: isPrimary ? WinampTheme.lcdGlow.opacity(0.3) : .clear, radius: 3)
        }
        .buttonStyle(.plain)
    }
}
