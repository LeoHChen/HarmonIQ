import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        Group {
            if library.allArtists.isEmpty {
                EmptyStateView(title: "No artists",
                               message: "Index a music drive to see artists.",
                               systemImage: "music.mic")
            } else {
                List(library.allArtists, id: \.self) { artist in
                    NavigationLink(value: artist) {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 32)
                            Text(artist)
                            Spacer()
                            Text("\(library.tracks(byArtist: artist).count)")
                                .foregroundStyle(.secondary)
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
                .navigationDestination(for: String.self) { artist in
                    ArtistDetailView(artist: artist)
                }
            }
        }
        .navigationTitle("Artists")
        .navigationBarTitleDisplayMode(.inline)
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
