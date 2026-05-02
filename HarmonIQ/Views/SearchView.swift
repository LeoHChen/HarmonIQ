import SwiftUI

struct SearchView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager
    @StateObject private var recents = RecentSearchStore()
    @State private var query: String = ""

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = library.search(trimmed)
        Group {
            if trimmed.isEmpty {
                if recents.queries.isEmpty {
                    EmptyStateView(title: "Search your library",
                                   message: "Find tracks by title, artist, or album.",
                                   systemImage: "magnifyingglass")
                } else {
                    RecentSearchesView(
                        recents: recents.queries,
                        onPick: { query = $0 },
                        onClear: { recents.clear() }
                    )
                }
            } else if results.isEmpty {
                EmptyStateView(title: "No matches",
                               message: "Try different keywords.",
                               systemImage: "questionmark.circle")
            } else {
                List(results) { track in
                    TrackRow(track: track, showAlbum: true)
                        .onTapGesture {
                            recents.record(trimmed)
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
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Title, artist, album…")
        .onSubmit(of: .search) {
            recents.record(trimmed)
        }
    }
}

private struct RecentSearchesView: View {
    let recents: [String]
    let onPick: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(recents, id: \.self) { q in
                    Button {
                        onPick(q)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(WinampTheme.lcdDim)
                                .frame(width: 24)
                            Text(q)
                                .font(WinampTheme.lcdFont(size: 13))
                                .foregroundStyle(Color(red: 0.85, green: 0.92, blue: 0.85))
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(WinampTheme.lcdDim)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                HStack {
                    SectionHeader("// RECENT SEARCHES")
                    Spacer()
                    Button(role: .destructive, action: onClear) {
                        Text("Clear")
                            .font(WinampTheme.lcdFont(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WinampTheme.lcdDim)
                }
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(WinampTheme.appBackground.ignoresSafeArea())
    }
}

/// Tiny LRU of recent search queries persisted in UserDefaults. Capped at 10
/// — anything older falls off when a fresh search bumps it.
@MainActor
final class RecentSearchStore: ObservableObject {
    private let key = "harmoniq.recentSearches"
    private let cap = 10

    @Published private(set) var queries: [String]

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        self.queries = saved
    }

    func record(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        var updated = queries.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        updated.insert(q, at: 0)
        if updated.count > cap { updated = Array(updated.prefix(cap)) }
        queries = updated
        UserDefaults.standard.set(updated, forKey: key)
    }

    func clear() {
        queries = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
