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
                            NavigationLink(value: key) {
                                AlbumCard(key: key)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .navigationDestination(for: LibraryStore.AlbumKey.self) { key in
                    AlbumDetailView(key: key)
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
        List {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    ArtworkView(track: tracks.first, size: 110, cornerRadius: 10)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(key.album).font(.title3.weight(.bold))
                        Text(key.artist).foregroundStyle(.secondary)
                        if let year = tracks.first?.year {
                            Text(String(year)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        HStack {
                            Button {
                                player.playAll(tracks, startAt: 0)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            Button {
                                var shuffled = tracks
                                shuffled.shuffle()
                                player.isShuffleEnabled = true
                                player.playAll(shuffled, startAt: 0)
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
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
