import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        ZStack {
            WinampTheme.appBackground.ignoresSafeArea()

            List {
                Section {
                    NavigationLink {
                        SmartPlayView()
                    } label: {
                        WinampNavRow(title: "SMART PLAY", icon: "wand.and.stars", isFeatured: true)
                    }
                } header: {
                    SectionHeader("// FOR YOU")
                } footer: {
                    Text("Curated queues built from your library — random, by artist, by genre, by decade, and more.")
                        .font(WinampTheme.lcdFont(size: 10))
                        .foregroundStyle(WinampTheme.lcdDim)
                }
                .listRowBackground(Color.clear)

                Section {
                    NavigationLink {
                        AllTracksView()
                    } label: {
                        WinampNavRow(title: "ALL TRACKS", icon: "music.note", count: library.tracks.count)
                    }
                    NavigationLink {
                        ArtistsView()
                    } label: {
                        WinampNavRow(title: "ARTISTS", icon: "music.mic", count: library.allArtists.count)
                    }
                    NavigationLink {
                        AlbumsView()
                    } label: {
                        WinampNavRow(title: "ALBUMS", icon: "square.stack", count: library.allAlbums.count)
                    }
                    NavigationLink {
                        FoldersView()
                    } label: {
                        WinampNavRow(title: "FOLDERS", icon: "folder", count: library.roots.count)
                    }
                } header: {
                    SectionHeader("// BROWSE")
                }
                .listRowBackground(Color.clear)

                if library.tracks.isEmpty {
                    Section {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            WinampNavRow(title: "ADD A MUSIC DRIVE", icon: "externaldrive.badge.plus", isFeatured: true)
                        }
                    } footer: {
                        Text("Pick a folder from the Files app — including external USB drives — to index your music collection.")
                            .font(WinampTheme.lcdFont(size: 10))
                            .foregroundStyle(WinampTheme.lcdDim)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("HARMONIQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(WinampTheme.lcdFont(size: 11))
            .foregroundStyle(WinampTheme.lcdDim)
            .padding(.top, 6)
    }
}

struct WinampNavRow: View {
    let title: String
    let icon: String
    var count: Int? = nil
    var isFeatured: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isFeatured ? WinampTheme.lcdGlow : WinampTheme.lcdDim)
                .frame(width: 28, height: 28)
                .background(WinampTheme.lcdBackground)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(WinampTheme.bevelDark))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: isFeatured ? WinampTheme.lcdGlow.opacity(0.4) : .clear, radius: 2)

            Text(title)
                .font(WinampTheme.lcdFont(size: 13))
                .foregroundStyle(isFeatured ? WinampTheme.lcdGlow : Color(red: 0.85, green: 0.92, blue: 0.85))

            Spacer()

            if let count = count {
                Text("\(count)")
                    .font(WinampTheme.lcdFont(size: 11))
                    .foregroundStyle(WinampTheme.lcdGlow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WinampTheme.lcdBackground)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(WinampTheme.bevelDark))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }
}
