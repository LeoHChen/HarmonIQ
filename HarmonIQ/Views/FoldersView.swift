import SwiftUI

/// Browses tracks by their on-drive folder structure.
struct FoldersView: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        Group {
            if library.roots.isEmpty {
                EmptyStateView(title: "No drives",
                               message: "Add a music drive from Settings to browse folders.",
                               systemImage: "folder")
            } else {
                List {
                    ForEach(library.roots) { root in
                        let rootTracks = library.tracks.filter { $0.rootBookmarkID == root.id }
                        NavigationLink {
                            FolderContentsView(root: root, path: [], tracks: rootTracks)
                                .navigationTitle(root.displayName)
                        } label: {
                            HStack {
                                Image(systemName: "externaldrive.fill")
                                    .foregroundStyle(.tint)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(root.displayName)
                                    Text("\(rootTracks.count) tracks").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                library.removeRoot(root)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            library.removeRoot(library.roots[idx])
                        }
                    }
                }
            }
        }
        .navigationTitle("Folders")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FolderContentsView: View {
    let root: LibraryRoot
    let path: [String]
    let tracks: [Track]
    @EnvironmentObject var player: AudioPlayerManager

    private struct Entry: Identifiable, Hashable {
        enum Kind: Hashable { case folder, track }
        let id: String
        let kind: Kind
        let name: String
        let track: Track?
    }

    var body: some View {
        let scoped = tracks.filter { Array($0.folderPath.prefix(path.count)) == path }

        let entries: [Entry] = {
            var folderNames: [String] = []
            var seen: Set<String> = []
            var leafTracks: [Track] = []
            for t in scoped {
                if t.folderPath.count > path.count {
                    let next = t.folderPath[path.count]
                    if !seen.contains(next) {
                        seen.insert(next)
                        folderNames.append(next)
                    }
                } else {
                    leafTracks.append(t)
                }
            }
            folderNames.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            leafTracks.sort { lhs, rhs in
                if let l = lhs.trackNumber, let r = rhs.trackNumber, l != r { return l < r }
                return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            }
            var result: [Entry] = folderNames.map { Entry(id: "f:\($0)", kind: .folder, name: $0, track: nil) }
            result.append(contentsOf: leafTracks.map { Entry(id: "t:\($0.stableID)", kind: .track, name: $0.displayTitle, track: $0) })
            return result
        }()

        let leafTracks = entries.compactMap { $0.kind == .track ? $0.track : nil }

        return List {
            if !leafTracks.isEmpty {
                Section {
                    Button {
                        player.playAll(leafTracks, startAt: 0)
                    } label: {
                        Label("Play this folder", systemImage: "play.fill")
                    }
                }
            }
            Section {
                ForEach(entries) { entry in
                    switch entry.kind {
                    case .folder:
                        NavigationLink {
                            FolderContentsView(root: root, path: path + [entry.name], tracks: tracks)
                                .navigationTitle(entry.name)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.yellow)
                                    .frame(width: 32)
                                Text(entry.name)
                            }
                        }
                    case .track:
                        if let track = entry.track {
                            TrackRow(track: track)
                                .onTapGesture {
                                    player.play(track: track, in: leafTracks)
                                }
                                .swipeActions {
                                    AddToPlaylistMenuButton(trackIDs: [track.stableID])
                                }
                        }
                    }
                }
            }
        }
    }
}
