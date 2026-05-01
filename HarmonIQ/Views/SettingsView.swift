import SwiftUI
import UniformTypeIdentifiers

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
                Text("Pick any folder visible in Files — including a USB drive — and HarmonIQ will recursively index its audio files.")
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

            Section("About") {
                LabeledContent("App", value: "HarmonIQ")
                LabeledContent("Version", value: "1.0")
                LabeledContent("Tracks indexed", value: "\(library.tracks.count)")
                LabeledContent("Playlists", value: "\(library.playlists.count)")
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
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let root = LibraryRoot(displayName: url.lastPathComponent, bookmark: bookmark)
            library.addRoot(root)
            indexer.index(root: root)
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
                Text(root.displayName).font(.body)
                Text(detailLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                indexer.index(root: root)
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
