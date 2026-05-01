import SwiftUI
import UniformTypeIdentifiers

struct SkinSettingsView: View {
    @EnvironmentObject var skinManager: SkinManager
    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        List {
            Section {
                NoSkinRow()
                ForEach(skinManager.skins) { skin in
                    SkinRow(skin: skin)
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import Winamp Skin (.wsz)…", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Skins")
            } footer: {
                Text("Tap a skin to apply it, or pick \"None\" to use the native SwiftUI player. Drop any classic Winamp 2.x skin (.wsz) in via the importer — same files that work in desktop Winamp.")
            }
        }
        .navigationTitle("Skins")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    do {
                        try skinManager.importSkin(from: url)
                    } catch {
                        importError = "Failed to import \(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }
            case .failure(let err):
                importError = err.localizedDescription
            }
        }
        .alert("Import Error", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }
}

private struct NoSkinRow: View {
    @EnvironmentObject var skinManager: SkinManager

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black)
                Image(systemName: "circle.slash")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 80, height: 34)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text("None (SwiftUI player)").font(.body)
                Text("Use the native HarmonIQ player").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if skinManager.activeSkin == nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            skinManager.clearSkin()
        }
    }
}

private struct SkinRow: View {
    let skin: WinampSkin
    @EnvironmentObject var skinManager: SkinManager

    var body: some View {
        HStack(spacing: 12) {
            // Tiny preview of the skin's main.bmp
            if let main = skin.main {
                Image(uiImage: main)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 80, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.15)))
            } else {
                Rectangle().fill(Color.gray)
                    .frame(width: 80, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(skin.displayName).font(.body)
                Text(skin.isBundled ? "Bundled" : "Imported")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if skinManager.activeSkin?.id == skin.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            skinManager.selectSkin(skin)
        }
        .swipeActions {
            if !skin.isBundled {
                Button(role: .destructive) {
                    skinManager.deleteImportedSkin(skin)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
