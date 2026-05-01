import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SmartPlayView()
                } label: {
                    Label("Smart Play", systemImage: "wand.and.stars")
                        .foregroundStyle(Color.accentColor)
                }
            } header: {
                Text("For You")
            } footer: {
                Text("Curated queues built from your library — random, by artist, by genre, by decade, and more.")
            }

            Section {
                NavigationLink {
                    AllTracksView()
                } label: {
                    Label("All Tracks", systemImage: "music.note")
                        .badge(library.tracks.count)
                }
                NavigationLink {
                    ArtistsView()
                } label: {
                    Label("Artists", systemImage: "music.mic")
                        .badge(library.allArtists.count)
                }
                NavigationLink {
                    AlbumsView()
                } label: {
                    Label("Albums", systemImage: "square.stack")
                        .badge(library.allAlbums.count)
                }
                NavigationLink {
                    FoldersView()
                } label: {
                    Label("Folders", systemImage: "folder")
                        .badge(library.roots.count)
                }
            } header: {
                Text("Browse")
            }

            if library.tracks.isEmpty {
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Add a music drive", systemImage: "externaldrive.badge.plus")
                            .foregroundStyle(.tint)
                    }
                } footer: {
                    Text("Pick a folder from the Files app — including external USB drives — to index your music collection.")
                }
            }
        }
        .navigationTitle("HarmonIQ")
    }
}
