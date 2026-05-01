import SwiftUI

struct SearchView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager
    @State private var query: String = ""

    var body: some View {
        let results = library.search(query)
        Group {
            if query.isEmpty {
                EmptyStateView(title: "Search your library",
                               message: "Find tracks by title, artist, or album.",
                               systemImage: "magnifyingglass")
            } else if results.isEmpty {
                EmptyStateView(title: "No matches",
                               message: "Try different keywords.",
                               systemImage: "questionmark.circle")
            } else {
                List(results) { track in
                    TrackRow(track: track, showAlbum: true)
                        .onTapGesture {
                            player.play(track: track, in: results)
                        }
                        .swipeActions {
                            AddToPlaylistMenuButton(trackIDs: [track.stableID])
                        }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Title, artist, album…")
    }
}
