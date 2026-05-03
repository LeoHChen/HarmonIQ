import SwiftUI

/// Library → Language hub (issue #86). Three buckets — Chinese / English /
/// Others — derived from a heuristic title/artist scan at index time.
/// Tapping a row drills into a filtered track list.
struct LanguageView: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        let counts = library.languageCounts
        Group {
            if library.tracks.isEmpty {
                EmptyStateView(title: "No tracks",
                               message: "Index a music drive to browse by language.",
                               systemImage: "globe")
            } else {
                List {
                    Section {
                        ForEach(TrackLanguage.displayOrder, id: \.self) { bucket in
                            NavigationLink {
                                LanguageDetailView(bucket: bucket)
                            } label: {
                                WinampNavRow(title: bucket.displayName.uppercased(),
                                             icon: bucket.iconName,
                                             count: counts[bucket] ?? 0)
                            }
                        }
                        .listRowBackground(Color.clear)
                    } header: {
                        SectionHeader("// LANGUAGE")
                    } footer: {
                        Text("Heuristic classification based on title and artist text. CJK characters map to Chinese (note: Japanese kanji and Korean hanja also land here in v1). Pure Latin maps to English. Anything else — accented Latin, hiragana/katakana-only, hangul-only, Cyrillic, Arabic, instrumentals with empty or numeric titles — lands in Others.")
                            .font(WinampTheme.lcdFont(size: 10))
                            .foregroundStyle(WinampTheme.lcdDim)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LanguageDetailView: View {
    let bucket: TrackLanguage
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        let tracks = library.tracks(forLanguage: bucket)
        Group {
            if tracks.isEmpty {
                EmptyStateView(title: "No \(bucket.displayName.lowercased()) tracks",
                               message: bucket == .others
                                   ? "Pure-instrumental, accented Latin, hangul, hiragana, Cyrillic and other scripts land here."
                                   : "Nothing classified as \(bucket.displayName) yet.",
                               systemImage: bucket.iconName)
            } else {
                List {
                    ForEach(tracks) { track in
                        TrackRow(track: track, showAlbum: true)
                            .onTapGesture {
                                player.play(track: track, in: tracks)
                            }
                            .swipeActions {
                                AddToPlaylistMenuButton(trackIDs: [track.stableID])
                            }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .navigationTitle(bucket.displayName)
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
