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
    @State private var refreshSheetRoot: LibraryRoot?

    // Ephemeral state for the About-screen easter egg (issue #123). Five taps
    // on the Version row within a 2s window flip `showLlama`; nothing here is
    // persisted, and `.onDisappear` resets all of it so the llama is hidden
    // again on every fresh entry into About.
    @State private var versionTapCount: Int = 0
    @State private var firstVersionTapAt: Date?
    @State private var showLlama: Bool = false
    private static let llamaTapWindow: TimeInterval = 2
    private static let llamaTapsRequired: Int = 5

    var body: some View {
        List {
            Section {
                ForEach(library.roots) { root in
                    DriveRow(root: root, onRefresh: { refreshSheetRoot = root })
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
                Text("Pick any folder visible in Files — including a USB drive — and HarmonIQ will recursively index its audio files. If the folder is read-only, the index is stored on this device and cross-device portability is disabled.\n\nTap the slider icon next to a drive to open Refresh, where you can rescan, reindex, fetch missing artwork, or rebuild the library.")
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
                Toggle(isOn: $artistPhotoFetcher.isOnlineFetchEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fetch artist photos online")
                        Text("Queries MusicBrainz, Wikidata, TheAudioDB, Wikipedia")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Online sources")
            } footer: {
                Text("Both toggles are off by default and independent. They control whether HarmonIQ may reach the internet to fill gaps. When album-art is on, HarmonIQ sends the album + artist of any track without local art to MusicBrainz to find a cover. When artist photos is on, HarmonIQ resolves the artist on MusicBrainz, then walks a fallback chain — Wikidata (Wikimedia Commons), TheAudioDB, and Wikipedia — and uses the first portrait that returns. Album covers are never used as artist photos; if no portrait is found, the tile shows a placeholder. Failures are silent — no other data leaves the device.\n\nThese toggles only authorise the lookups; trigger one with a drive's Refresh sheet.")
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
                Button(action: registerVersionTap) {
                    LabeledContent("Version", value: BuildInfo.version)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                if showLlama {
                    HStack {
                        Spacer()
                        LlamaEasterEgg()
                            .padding(.top, 8)
                        Spacer()
                    }
                }
            } header: {
                Text("About")
            } footer: {
                Text("Tap “Copy build info” to grab a multi-line block (version + build + commit + tag + timestamp) for bug reports.")
            }
            .onDisappear {
                showLlama = false
                versionTapCount = 0
                firstVersionTapAt = nil
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            DocumentFolderPicker { url in
                addRoot(from: url)
            }
        }
        .sheet(item: $refreshSheetRoot) { root in
            NavigationView {
                RefreshDriveSheet(root: root)
            }
        }
    }

    /// Counts taps on the Version row. A 5-tap burst within `llamaTapWindow`
    /// reveals the llama; the counter resets on success or whenever the
    /// elapsed window is exceeded.
    private func registerVersionTap() {
        let now = Date()
        if let first = firstVersionTapAt, now.timeIntervalSince(first) > Self.llamaTapWindow {
            firstVersionTapAt = now
            versionTapCount = 1
            return
        }
        if firstVersionTapAt == nil {
            firstVersionTapAt = now
        }
        versionTapCount += 1
        if versionTapCount >= Self.llamaTapsRequired {
            showLlama = true
            versionTapCount = 0
            firstVersionTapAt = nil
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
    let onRefresh: () -> Void
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
            // Lives outside the Refresh sheet because it's a recovery
            // affordance, not a maintenance action.
            Button {
                library.reloadDrive(root)
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reload drive")

            // Single Refresh entry point per drive (issue #98). Opens
            // a sheet with Quick refresh / Reindex / Online lookups /
            // Rebuild — covers everything a user used to need a row
            // of buttons for.
            Button {
                onRefresh()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Refresh drive")
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

/// Single consolidated maintenance entry point per drive (issue #98).
/// Replaces the previous sprawl of Reindex / Refresh missing artwork /
/// Refresh missing artist photos / Rescan artwork / Reclassify language /
/// Rebuild library buttons. Each section here calls into the existing
/// `LibraryStore` / `MusicIndexer` / `ArtworkFetcher` / `ArtistPhotoFetcher`
/// methods — this is a UI relayout, not a behaviour change.
private struct RefreshDriveSheet: View {
    let root: LibraryRoot
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var indexer: MusicIndexer
    @ObservedObject private var artworkFetcher = ArtworkFetcher.shared
    @ObservedObject private var artistPhotoFetcher = ArtistPhotoFetcher.shared
    @Environment(\.dismiss) private var dismiss

    @State private var quickStatus: String = ""
    @State private var forceReindex = false
    @State private var showReindexConfirm = false
    @State private var showRebuildConfirm = false
    @State private var showAlbumArtConfirm = false
    @State private var showArtistPhotoConfirm = false
    @State private var showAdvanced = false

    var body: some View {
        Form {
            // 1. Quick refresh — cheapest, no confirmation, no network.
            Section {
                Button {
                    runQuickRefresh()
                } label: {
                    Label("Quick refresh", systemImage: "sparkles")
                }
                .disabled(indexer.isIndexing)
                if !quickStatus.isEmpty {
                    Text(quickStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Quick")
            } footer: {
                Text("Re-reads any album covers you dropped into <Drive>/HarmonIQ/Artwork/, recomputes language buckets (Chinese / English / Others) for every track, and refreshes internal display caches. No network, no audio re-read. Safe to run any time.")
            }

            // 2. Reindex tracks — incremental walk; force toggle exposes
            // the previous "force=true" path that bypasses the cheap-check.
            Section {
                Toggle("Force re-read all files", isOn: $forceReindex)
                Button {
                    if forceReindex {
                        showReindexConfirm = true
                    } else {
                        indexer.index(root: root, force: false)
                    }
                } label: {
                    Label("Reindex tracks", systemImage: "arrow.clockwise")
                }
                .disabled(indexer.isIndexing)
            } header: {
                Text("Reindex")
            } footer: {
                Text("Walks the drive for new or changed audio files and updates per-track metadata + embedded artwork. Existing entries are kept. Force re-read ignores the fast-check fingerprint and inspects every file — slower, only needed if a previous scan looked stale.")
            }

            // 3. Online sources — gated by the umbrella toggles. When a
            // toggle is off, the row is disabled with a hint pointing
            // back to Settings → Online sources.
            onlineSection

            // 4. Advanced — the destructive Rebuild lives here, hidden
            // by default so a casual user can't tap it accidentally.
            Section {
                DisclosureGroup(isExpanded: $showAdvanced) {
                    Button(role: .destructive) {
                        showRebuildConfirm = true
                    } label: {
                        Label("Rebuild library from scratch", systemImage: "arrow.counterclockwise.circle")
                    }
                    .disabled(indexer.isIndexing)
                } label: {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
            } footer: {
                Text("Rebuild deletes this drive's library.json and runs a fresh full scan. Use it only if the album list is duplicated or has stale entries that Reindex hasn't been able to clear. Playlists, favorites, and smart playlists are preserved as long as audio files stay at the same paths.")
            }
        }
        .navigationTitle("Refresh")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        // Force-reindex confirmation — only shown when the toggle is on
        // and the user taps Reindex.
        .confirmationDialog("Force re-read all files?",
                            isPresented: $showReindexConfirm,
                            titleVisibility: .visible) {
            Button("Reindex everything") {
                indexer.index(root: root, force: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This walks every audio file on \(root.displayName), bypassing the fast-check fingerprint. Slower than a normal reindex; only use if you suspect the index is stale.")
        }
        .confirmationDialog("Fetch missing album art online?",
                            isPresented: $showAlbumArtConfirm,
                            titleVisibility: .visible) {
            Button("Start") {
                artworkFetcher.refreshMissingArtwork(for: root)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sends one MusicBrainz query per album missing artwork on \(root.displayName), at most 1 request per second. Failures are silent.")
        }
        .confirmationDialog("Fetch missing artist photos online?",
                            isPresented: $showArtistPhotoConfirm,
                            titleVisibility: .visible) {
            Button("Start") {
                artistPhotoFetcher.refreshMissingArtistPhotos(for: root)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sends each missing artist's name to MusicBrainz, then walks a fallback chain (Wikidata → TheAudioDB → Wikipedia) until a portrait is found, at most 1 MusicBrainz request per second on \(root.displayName). Failures are silent.")
        }
        .confirmationDialog("Rebuild library from scratch?",
                            isPresented: $showRebuildConfirm,
                            titleVisibility: .visible) {
            Button("Rebuild", role: .destructive) {
                library.rebuildLibrary(for: root)
                indexer.index(root: root, force: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes \(root.displayName)'s library.json and runs a fresh scan. Playlists survive as long as audio files stay at the same paths. The bookmark and favorites are preserved.")
        }
    }

    @ViewBuilder
    private var onlineSection: some View {
        let albumArtOn = artworkFetcher.isOnlineFetchEnabled
        let artistPhotosOn = artistPhotoFetcher.isOnlineFetchEnabled
        let anyOn = albumArtOn || artistPhotosOn

        Section {
            if !anyOn {
                Label("Online lookup is off", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
                Text("Enable Fetch missing album art online or Fetch artist photos online in Settings → Online sources to use this section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if albumArtOn {
                    Button {
                        showAlbumArtConfirm = true
                    } label: {
                        Label("Fetch album art", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(artworkFetcher.isRefreshing)
                }
                if artistPhotosOn {
                    Button {
                        showArtistPhotoConfirm = true
                    } label: {
                        Label("Fetch artist photos", systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(artistPhotoFetcher.isRefreshing)
                }

                // Album-art fetcher progress + Stop. Shared across all
                // drives by design (the fetcher itself only runs one
                // batch at a time).
                if artworkFetcher.isRefreshing {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(artworkFetcher.refreshStatusMessage).font(.caption)
                        ProgressView(value: artworkFetcher.refreshProgress)
                        Button("Stop", role: .destructive) { artworkFetcher.cancelRefresh() }
                    }
                } else if !artworkFetcher.refreshStatusMessage.isEmpty {
                    Text(artworkFetcher.refreshStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if artistPhotoFetcher.isRefreshing {
                    VStack(alignment: .leading, spacing: 6) {
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
        } header: {
            Text("Fetch from the internet")
        } footer: {
            Text("Album-art and artist-photo lookups are independent and respect the umbrella toggles in Settings → Online sources. Each batch runs at most one query per second. Tap Stop to cancel mid-batch — what's already downloaded is kept.")
        }
    }

    private func runQuickRefresh() {
        // Three cheap, idempotent operations rolled into one button.
        // Every step is a no-op when nothing's stale, so spamming this
        // is harmless. Status string is best-effort — we surface the
        // most informative bit.
        let result = library.rescanArtwork(for: root)
        let reclassified = library.reclassifyAllLanguages()
        library.invalidateArtistImageCache()

        var parts: [String] = []
        if result.tracksUpdated > 0 {
            parts.append("Adopted \(result.albumsAdopted) cover(s) — patched \(result.tracksUpdated) track(s).")
        }
        if reclassified > 0 {
            parts.append("Reclassified \(reclassified) track(s) by language.")
        }
        if parts.isEmpty {
            parts.append("Up to date — nothing to update on \(root.displayName).")
        }
        quickStatus = parts.joined(separator: " ")
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
