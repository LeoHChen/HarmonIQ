import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager
    @State private var showNowPlaying = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                NavigationStack { LibraryView() }
                    .tabItem { Label("Library", systemImage: "music.note.list") }

                NavigationStack { SearchView() }
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }

                NavigationStack { PlaylistsView() }
                    .tabItem { Label("Playlists", systemImage: "music.note.house") }

                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.currentTrack != nil {
                    MiniPlayerView()
                        .onTapGesture { showNowPlaying = true }
                }
            }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LibraryStore.shared)
        .environmentObject(AudioPlayerManager.shared)
        .environmentObject(MusicIndexer.shared)
}
