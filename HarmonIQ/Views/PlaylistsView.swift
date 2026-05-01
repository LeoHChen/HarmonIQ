import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        Group {
            if library.playlists.isEmpty {
                EmptyStateView(title: "No playlists",
                               message: "Tap + to create your first playlist.",
                               systemImage: "music.note.list")
            } else {
                List {
                    ForEach(library.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note.list")
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .frame(width: 36, height: 36)
                                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                    Text("\(playlist.trackIDs.count) tracks").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Playlist", isPresented: $showCreate) {
            TextField("Name", text: $newName)
            Button("Create") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                _ = library.createPlaylist(name: trimmed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give your playlist a name.")
        }
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets {
            let playlist = library.playlists[idx]
            library.deletePlaylist(playlist)
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager
    @State private var renameSheet = false
    @State private var newName = ""

    var body: some View {
        let tracks = library.tracks(for: playlist)
        Group {
            if tracks.isEmpty {
                EmptyStateView(title: "Empty playlist",
                               message: "Swipe a track and choose Add to Playlist to add tracks.",
                               systemImage: "music.note.list")
            } else {
                List {
                    Section {
                        Button {
                            player.playAll(tracks, startAt: 0)
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                        }
                        Button {
                            var shuffled = tracks
                            shuffled.shuffle()
                            player.isShuffleEnabled = true
                            player.playAll(shuffled, startAt: 0)
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                        }
                    }
                    Section {
                        ForEach(tracks) { track in
                            TrackRow(track: track, showAlbum: true)
                                .onTapGesture {
                                    player.play(track: track, in: tracks)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        library.removeTrack(track.stableID, from: playlist)
                                    } label: {
                                        Label("Remove", systemImage: "minus.circle")
                                    }
                                }
                        }
                        .onMove { from, to in
                            library.reorderTracks(in: playlist, from: from, to: to)
                        }
                    }
                }
                .toolbar { EditButton() }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newName = playlist.name
                        renameSheet = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        library.deletePlaylist(playlist)
                    } label: {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Playlist", isPresented: $renameSheet) {
            TextField("Name", text: $newName)
            Button("Save") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                library.renamePlaylist(playlist, to: trimmed)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
