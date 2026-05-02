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
    @State private var showPicker = false

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
            } header: {
                Text("Feedback")
            } footer: {
                Text("Tip: tap “Copy build info” before “Report a bug” — paste it into the issue so we can triage faster.")
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
            Button {
                // Explicit user tap → force a full incremental walk
                // (skip the cheap fingerprint short-circuit). Otherwise
                // a stale fingerprint could silently say "up to date"
                // when the drive's library.json doesn't reflect what's
                // actually on disk.
                indexer.index(root: root, force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
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
