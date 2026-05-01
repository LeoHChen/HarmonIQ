import SwiftUI

struct AllTracksView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        let sorted = library.tracks.sorted { lhs, rhs in
            lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
        Group {
            if sorted.isEmpty {
                EmptyStateView(title: "No tracks yet",
                               message: "Add a music drive from Settings to start indexing.",
                               systemImage: "music.note.list")
            } else {
                List {
                    Section {
                        Button {
                            player.playAll(sorted, startAt: 0)
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                        }
                        Button {
                            var shuffled = sorted
                            shuffled.shuffle()
                            player.isShuffleEnabled = true
                            player.playAll(shuffled, startAt: 0)
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                        }
                    }

                    Section {
                        ForEach(sorted) { track in
                            TrackRow(track: track, showAlbum: true)
                                .onTapGesture {
                                    player.play(track: track, in: sorted)
                                }
                                .swipeActions {
                                    AddToPlaylistMenuButton(trackIDs: [track.stableID])
                                }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("All Tracks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AddToPlaylistMenuButton: View {
    let trackIDs: [String]
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        Menu {
            if library.playlists.isEmpty {
                Text("No playlists yet")
            } else {
                ForEach(library.playlists) { playlist in
                    Button(playlist.name) {
                        library.addTracks(trackIDs, to: playlist)
                    }
                }
            }
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }
        .tint(.indigo)
    }
}
