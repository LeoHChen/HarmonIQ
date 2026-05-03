import SwiftUI
import UniformTypeIdentifiers

/// Canonical feedback URLs for the GitHub repo. Linked from Settings → Feedback
/// (issue #59). The new-issue URLs include a `labels=...` query so the GitHub
/// form opens with the right label pre-selected; the optional `template=` query
/// is harmless when the repo doesn't have an issue template (GitHub falls back
/// to a blank issue with the label set).
private enum FeedbackURL {
    static let repo = URL(string: "https://github.com/LeoHChen/HarmonIQ")!
    static let issues = URL(string: "https://github.com/LeoHChen/HarmonIQ/issues")!
    static let featureRequest = URL(string: "https://github.com/LeoHChen/HarmonIQ/issues/new?labels=enhancement&template=feature_request.md")!
    static let bugReport = URL(string: "https://github.com/LeoHChen/HarmonIQ/issues/new?labels=bug&template=bug_report.md")!
}

struct SettingsView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var indexer: MusicIndexer
    @StateObject private var artworkFetcher = ArtworkFetcher.shared
    @StateObject private var artistPhotoFetcher = ArtistPhotoFetcher.shared
    @State private var showPicker = false
    @State private var bulkConfirmRoot: LibraryRoot?
    @State private var artistBulkConfirmRoot: LibraryRoot?
    @State private var rebuildConfirmRoot: LibraryRoot?
    @State private var reclassifyStatus: String = ""

    var body: some View {
        List {
            Section {
                ForEach(library.roots) { root in
                    DriveRow(root: root)
                }
                .onDelete { offsets in
                    for idx in offsets {
                        library.removeRoot(library.roots[idx])
                    }
                }
                Button {
                    showPicker = true
                } label: {
                    Label("Add Music Drive…", systemImage: "externaldrive.badge.plus")
                }
            } header: {
                Text("Music Drives")
            } footer: {
                Text("Pick any folder visible in Files — including a USB drive — and HarmonIQ will recursively index its audio files. If the folder is read-only, the index is stored on this device and cross-device portability is disabled.")
            }

            if indexer.isIndexing {
                Section("Indexing") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(indexer.statusMessage).font(.caption)
                        ProgressView(value: indexer.progress)
                        Button("Cancel", role: .destructive) { indexer.cancel() }
                    }
                }
            } else if !indexer.statusMessage.isEmpty {
                Section("Last Run") {
                    Text(indexer.statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(isOn: $artworkFetcher.isOnlineFetchEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fetch missing album art online")
                        Text("Queries MusicBrainz / Cover Art Archive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if artworkFetcher.isOnlineFetchEnabled {
                    ForEach(library.roots) { root in
                        Button {
                            bulkConfirmRoot = root
                        } label: {
                            Label("Refresh missing artwork — \(root.displayName)",
                                  systemImage: "photo.on.rectangle.angled")
                        }
                        .disabled(artworkFetcher.isRefreshing)
                    }
                    if artworkFetcher.isRefreshing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(artworkFetcher.refreshStatusMessage).font(.caption)
                            ProgressView(value: artworkFetcher.refreshProgress)
                            Button("Stop", role: .destructive) { artworkFetcher.cancelRefresh() }
                        }
                    } else if !artworkFetcher.refreshStatusMessage.isEmpty {
                        Text(artworkFetcher.refreshStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $artistPhotoFetcher.isOnlineFetchEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fetch artist photos online")
                        Text("Queries MusicBrainz, Wikidata, TheAudioDB, Wikipedia")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if artistPhotoFetcher.isOnlineFetchEnabled {
                    ForEach(library.roots) { root in
                        Button {
                            artistBulkConfirmRoot = root
                        } label: {
                            Label("Refresh missing artist photos — \(root.displayName)",
                                  systemImage: "person.crop.circle.badge.plus")
                        }
                        .disabled(artistPhotoFetcher.isRefreshing)
                    }
                    if artistPhotoFetcher.isRefreshing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(artistPhotoFetcher.refreshStatusMessage).font(.caption)
                            ProgressView(value: artistPhotoFetcher.refreshProgress)
                            Button("Stop", role: .destructive) { artistPhotoFetcher.cancelRefresh() }
                        }
                    } else if !artistPhotoFetcher.refreshStatusMessage.isEmpty {
                        Text(artistPhotoFetcher.refreshStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(library.roots) { root in
                    Button {
                        library.rescanArtwork(for: root)
                    } label: {
                        Label("Rescan artwork on disk — \(root.displayName)",
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                if !library.artworkRescanStatus.isEmpty {
                    Text(library.artworkRescanStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Artwork")
            } footer: {
                Text("Both toggles are off by default and independent. When album-art is on, HarmonIQ sends the album + artist of any track without local art to MusicBrainz to find a cover. When artist photos is on, HarmonIQ resolves the artist on MusicBrainz, then walks a fallback chain — Wikidata (Wikimedia Commons), TheAudioDB, and Wikipedia — and uses the first portrait that returns. Album covers are never used as artist photos; if no portrait is found, the tile shows a placeholder. Failures are silent — no other data leaves the device.\n\n“Rescan artwork on disk” adopts any album covers you dropped into <Drive>/HarmonIQ/Artwork/ matching the sha1(albumArtist|album).jpg naming convention. Files that don't match a known album are ignored.")
            }

            Section {
                ForEach(library.roots) { root in
                    Button(role: .destructive) {
                        rebuildConfirmRoot = root
                    } label: {
                        Label("Rebuild library — \(root.displayName)",
                              systemImage: "arrow.counterclockwise.circle")
                    }
                    .disabled(indexer.isIndexing)
                }
                Button {
                    let changed = library.reclassifyAllLanguages()
                    reclassifyStatus = changed == 0
                        ? "Languages already up to date — \(library.tracks.count) track(s) checked."
                        : "Reclassified \(changed) of \(library.tracks.count) track(s)."
                } label: {
                    Label("Reclassify all tracks by language", systemImage: "globe")
                }
                .disabled(library.tracks.isEmpty)
                if !reclassifyStatus.isEmpty {
                    Text(reclassifyStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Maintenance")
            } footer: {
                Text("Rebuild wipes the drive's library.json and runs a fresh full scan — use it if the album list is duplicated or has stale entries (issue #88). Reclassify recomputes the Chinese / English / Others bucket on every track without re-reading audio (issue #86). Playlists, favorites, and smart playlists are preserved by both actions.")
            }

            Section {
                NavigationLink {
                    SkinSettingsView()
                } label: {
                    Label("Skins", systemImage: "paintpalette")
                }
                NavigationLink {
                    VisualizerSettingsView()
                } label: {
                    Label("Visualizer", systemImage: "waveform")
                }
            } header: {
                Text("Appearance")
            }

            Section {
                NavigationLink {
                    AISettingsView()
                } label: {
                    Label("AI Smart Play", systemImage: "wand.and.stars")
                }
            } header: {
                Text("AI")
            } footer: {
                Text("Optional — adds AI-driven Smart Play modes (Vibe Match, Storyteller, Sonic Contrast). Bring your own Anthropic API key. Calls are billed to your account.")
            }

            Section {
                Link(destination: FeedbackURL.featureRequest) {
                    Label("Request a feature", systemImage: "lightbulb")
                }
                Link(destination: FeedbackURL.bugReport) {
                    Label("Report a bug", systemImage: "ladybug")
                }
                Link(destination: FeedbackURL.issues) {
                    Label("Browse open issues", systemImage: "bubble.left.and.bubble.right")
                }
                Link(destination: FeedbackURL.repo) {
                    Label("Star on GitHub", systemImage: "star")
                }
                Button {
                    UIPasteboard.general.string = BuildInfo.clipboardSummary
                } label: {
                    Label("Copy build info", systemImage: "doc.on.clipboard")
                }
                Button {
                    UIPasteboard.general.string = "subsystem:net.leochen.harmoniq category:playback"
                } label: {
                    Label("Copy playback log filter", systemImage: "doc.on.clipboard.fill")
                }
            } header: {
                Text("Feedback")
            } footer: {
                Text("Tip: tap “Copy build info” before “Report a bug” — paste it into the issue so we can triage faster. For playback bugs (e.g. mid-track aborts), use “Copy playback log filter” and paste it into Console.app while connected to your iPhone to capture the diagnostic stream.")
            }

            Section {
                LabeledContent("App", value: "HarmonIQ")
                LabeledContent("Version", value: BuildInfo.version)
                LabeledContent("Build", value: BuildInfo.build)
                LabeledContent("Commit", value: BuildInfo.gitCommit)
                LabeledContent("Release tag", value: BuildInfo.gitTag)
                LabeledContent("Built at", value: BuildInfo.builtAt)
                LabeledContent("Tracks indexed", value: "\(library.tracks.count)")
                LabeledContent("Playlists", value: "\(library.playlists.count)")
                Button {
                    UIPasteboard.general.string = BuildInfo.clipboardSummary
                } label: {
                    Label("Copy build info", systemImage: "doc.on.doc")
                }
            } header: {
                Text("About")
            } footer: {
                Text("Tap “Copy build info” to grab a multi-line block (version + build + commit + tag + timestamp) for bug reports.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            DocumentFolderPicker { url in
                addRoot(from: url)
            }
        }
        .confirmationDialog("Refresh missing artwork?",
                            isPresented: Binding(get: { bulkConfirmRoot != nil },
                                                 set: { if !$0 { bulkConfirmRoot = nil } }),
                            titleVisibility: .visible) {
            Button("Start refresh") {
                if let r = bulkConfirmRoot {
                    artworkFetcher.refreshMissingArtwork(for: r)
                }
                bulkConfirmRoot = nil
            }
            Button("Cancel", role: .cancel) { bulkConfirmRoot = nil }
        } message: {
            Text("This sends one MusicBrainz query per album missing artwork on \(bulkConfirmRoot?.displayName ?? "this drive"), at most 1 request per second. Failures are silent.")
        }
        .confirmationDialog("Refresh missing artist photos?",
                            isPresented: Binding(get: { artistBulkConfirmRoot != nil },
                                                 set: { if !$0 { artistBulkConfirmRoot = nil } }),
                            titleVisibility: .visible) {
            Button("Start refresh") {
                if let r = artistBulkConfirmRoot {
                    artistPhotoFetcher.refreshMissingArtistPhotos(for: r)
                }
                artistBulkConfirmRoot = nil
            }
            Button("Cancel", role: .cancel) { artistBulkConfirmRoot = nil }
        } message: {
            Text("This sends each missing artist's name to MusicBrainz, then walks a fallback chain (Wikidata → TheAudioDB → Wikipedia) until a portrait is found, at most 1 MusicBrainz request per second on \(artistBulkConfirmRoot?.displayName ?? "this drive"). Failures are silent.")
        }
        .confirmationDialog("Rebuild library from scratch?",
                            isPresented: Binding(get: { rebuildConfirmRoot != nil },
                                                 set: { if !$0 { rebuildConfirmRoot = nil } }),
                            titleVisibility: .visible) {
            Button("Rebuild", role: .destructive) {
                if let r = rebuildConfirmRoot {
                    library.rebuildLibrary(for: r)
                    indexer.index(root: r, force: true)
                }
                rebuildConfirmRoot = nil
            }
            Button("Cancel", role: .cancel) { rebuildConfirmRoot = nil }
        } message: {
            Text("Deletes \(rebuildConfirmRoot?.displayName ?? "this drive")'s library.json and runs a fresh scan. Playlists survive as long as audio files stay at the same paths. The bookmark and favorites are preserved.")
        }
    }

    private func addRoot(from url: URL) {
        // The URL handed to us by UIDocumentPickerViewController is only
        // transiently accessible. To capture *write* access in the bookmark
        // we must explicitly start security scope before serializing it —
        // otherwise the bookmark resolves later as read-only and every
        // folder ends up flagged isReadOnly even when it's a writable
        // location on the device.
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let root = LibraryRoot(displayName: url.lastPathComponent, bookmark: bookmark)
            library.addRoot(root)
            // Only run a fresh scan if the drive doesn't already have an index. A drive
            // previously indexed (here or on another iPhone) just gets adopted.
            let alreadyIndexed = library.tracks.contains { $0.rootBookmarkID == root.id }
            if !alreadyIndexed {
                indexer.index(root: root)
            }
        } catch {
            print("[HarmonIQ] Bookmark failed: \(error)")
        }
    }
}

private struct DriveRow: View {
    let root: LibraryRoot
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var indexer: MusicIndexer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(root.displayName).font(.body)
                    if root.isReadOnly {
                        Text("Read-only")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.25), in: Capsule())
                            .foregroundStyle(Color.orange)
                    }
                }
                Text(detailLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Reload — re-reads the drive's library.json without
            // walking the filesystem. Use this when you plugged the
            // drive in mid-session and the songs aren't showing yet.
            Button {
                library.reloadDrive(root)
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reload drive")

            // Reindex — full incremental walk; force=true skips the
            // cheap-check so an explicit tap never silently no-ops.
            Button {
                indexer.index(root: root, force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reindex drive")
            .disabled(indexer.isIndexing)
        }
        .swipeActions {
            Button(role: .destructive) {
                library.removeRoot(root)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var detailLine: String {
        var parts: [String] = ["\(root.trackCount) tracks"]
        if let last = root.lastIndexed {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            parts.append("indexed \(f.string(from: last))")
        }
        return parts.joined(separator: " · ")
    }
}

/// SwiftUI wrapper around UIDocumentPickerViewController for folder selection.
struct DocumentFolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
