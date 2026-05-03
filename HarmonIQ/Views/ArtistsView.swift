import SwiftUI

/// Artists browse view (issue #89). Visual grid mirroring `AlbumsView` —
/// each tile shows a real artist photo if one exists locally, otherwise a
/// representative album cover (PR #92), otherwise a Winamp-themed
/// placeholder.
///
/// Network-fetched artist photos (issue #93) are opt-in via
/// Settings → Artwork. When the toggle is off, this view never hits the
/// network. When on, every visible tile fires a single
/// `ArtistPhotoFetcher.fetchIfMissing` call on appearance — the fetcher's
/// in-flight + negative cache + 1-req/sec rate limiter handles dedup.
struct ArtistsView: View {
    @EnvironmentObject var library: LibraryStore
    @StateObject private var artistPhotoFetcher = ArtistPhotoFetcher.shared

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    var body: some View {
        Group {
            if library.allArtists.isEmpty {
                EmptyStateView(title: "No artists",
                               message: "Index a music drive to see artists.",
                               systemImage: "music.mic")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(library.allArtists, id: \.self) { artist in
                            NavigationLink {
                                ArtistDetailView(artist: artist)
                            } label: {
                                ArtistCard(artist: artist)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                // Opportunistic fetch — the fetcher gates
                                // on the toggle, online state, and dedup
                                // caches, so this is cheap on every cell.
                                if let drive = library.preferredDriveForArtist(artist) {
                                    artistPhotoFetcher.fetchIfMissing(artist: artist, rootBookmarkID: drive)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Artists")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ArtistCard: View {
    let artist: String
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        let imageSource = library.artistImage(forArtist: artist)
        let trackCount = library.tracks(byArtist: artist).count
        VStack(alignment: .leading, spacing: 6) {
            // Use a circular crop for artist tiles to visually distinguish
            // them from album tiles (square). When no artwork at all is
            // attached to the artist's tracks, render the Winamp-themed
            // placeholder glyph.
            ArtistTile(imageSource: imageSource, size: 150)
                .frame(maxWidth: .infinity)
            Text(artist)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("\(trackCount) track\(trackCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Circular artist tile. Renders, in order of preference: a real artist
/// photo (when one exists in the local cache), the representative album
/// cover, or a microphone glyph placeholder.
private struct ArtistTile: View {
    let imageSource: LibraryStore.ArtistImageSource?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    WinampTheme.panelGradient
                    Image(systemName: "music.mic")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(WinampTheme.lcdGlow.opacity(0.7))
                        .shadow(color: WinampTheme.lcdGlow.opacity(0.4), radius: 2)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(WinampTheme.bevelLight.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }

    private func loadImage() -> UIImage? {
        guard let source = imageSource else { return nil }
        switch source {
        case .artistPhoto(let filename):
            let url = LibraryStore.shared.artistPhotoDirectory.appendingPathComponent(filename)
            return UIImage(contentsOfFile: url.path)
        case .albumCover(let filename):
            let url = LibraryStore.shared.artworkDirectory.appendingPathComponent(filename)
            return UIImage(contentsOfFile: url.path)
        }
    }
}

struct ArtistDetailView: View {
    let artist: String
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        let tracks = library.tracks(byArtist: artist).sorted { lhs, rhs in
            if lhs.displayAlbum != rhs.displayAlbum {
                return lhs.displayAlbum.localizedStandardCompare(rhs.displayAlbum) == .orderedAscending
            }
            if let l = lhs.trackNumber, let r = rhs.trackNumber, l != r { return l < r }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
        let albumKeys = Array(Set(tracks.map { LibraryStore.AlbumKey(album: $0.displayAlbum, artist: artist) })).sorted {
            $0.album.localizedStandardCompare($1.album) == .orderedAscending
        }
        List {
            ForEach(albumKeys) { key in
                Section(key.album) {
                    ForEach(library.tracks(forAlbum: key)) { track in
                        TrackRow(track: track)
                            .onTapGesture {
                                player.play(track: track, in: tracks)
                            }
                            .swipeActions {
                                AddToPlaylistMenuButton(trackIDs: [track.stableID])
                            }
                    }
                }
            }
        }
        .navigationTitle(artist)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        player.playAll(tracks, startAt: 0)
                    } label: { Label("Play All", systemImage: "play") }
                    Button {
                        player.isShuffleEnabled = true
                        var shuffled = tracks
                        shuffled.shuffle()
                        player.playAll(shuffled, startAt: 0)
                    } label: { Label("Shuffle", systemImage: "shuffle") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
