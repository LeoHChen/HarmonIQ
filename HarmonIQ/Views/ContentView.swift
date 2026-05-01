import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var skinManager: SkinManager
    @State private var showNowPlaying = false

    var body: some View {
        ZStack(alignment: .bottom) {
            WinampTheme.appBackground
                .ignoresSafeArea()
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
            .scrollContentBackground(.hidden)
        }
        .sheet(isPresented: $showNowPlaying) {
            if skinManager.activeSkin != nil {
                SkinnedMainView()
            } else {
                NowPlayingView()
            }
        }
        // Auto-present the player when the user taps a track anywhere in the
        // app. AudioPlayerManager increments presentNowPlayingTick on every
        // user-initiated play() / playAll() / playSmart() call (but NOT on
        // Next/Previous from inside the player), so the sheet pops up on
        // first selection without re-triggering as playback advances.
        .onReceive(player.$presentNowPlayingTick.dropFirst()) { _ in
            showNowPlaying = true
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LibraryStore.shared)
        .environmentObject(AudioPlayerManager.shared)
        .environmentObject(MusicIndexer.shared)
}
