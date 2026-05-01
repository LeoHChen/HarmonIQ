import Foundation
import Combine
import UIKit

/// Owns the list of installed skins (bundled + imported) and the active selection.
/// Active skin id is persisted to UserDefaults; the skin itself is reparsed on launch.
@MainActor
final class SkinManager: ObservableObject {
    static let shared = SkinManager()

    @Published private(set) var skins: [WinampSkin] = []
    @Published private(set) var activeSkin: WinampSkin?

    private let activeSkinKey = "harmoniq.activeSkinName"

    init() {
        reload()
        // Restore last active skin (by display name).
        let savedName = UserDefaults.standard.string(forKey: activeSkinKey)
        if let name = savedName, let match = skins.first(where: { $0.displayName == name }) {
            activeSkin = match
        } else {
            activeSkin = skins.first
        }
    }

    /// Re-scans the bundled `Skins/` folder and the imported skins directory.
    /// Call this after importing a new .wsz.
    func reload() {
        var loaded: [WinampSkin] = []

        // 1. Bundled skins (read-only, ship inside the app).
        let bundleSkinsDir = Bundle.main.url(forResource: "Skins", withExtension: nil)
            ?? Bundle.main.bundleURL.appendingPathComponent("Skins", isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(at: bundleSkinsDir, includingPropertiesForKeys: nil) {
            for url in entries where url.pathExtension.lowercased() == "wsz" {
                if let skin = try? SkinLoader.load(from: url, isBundled: true) {
                    loaded.append(skin)
                }
            }
        }

        // 2. User-imported skins.
        let importedDir = Self.importedSkinsDirectory()
        if let entries = try? FileManager.default.contentsOfDirectory(at: importedDir, includingPropertiesForKeys: nil) {
            for url in entries where url.pathExtension.lowercased() == "wsz" {
                if let skin = try? SkinLoader.load(from: url, isBundled: false) {
                    loaded.append(skin)
                }
            }
        }

        loaded.sort {
            // Bundled first, then alphabetical inside each group.
            if $0.isBundled != $1.isBundled { return $0.isBundled }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        skins = loaded
    }

    func selectSkin(_ skin: WinampSkin) {
        activeSkin = skin
        UserDefaults.standard.set(skin.displayName, forKey: activeSkinKey)
    }

    /// Copy a user-picked .wsz into the imported-skins directory and reload. Returns
    /// the freshly-loaded skin on success.
    @discardableResult
    func importSkin(from sourceURL: URL) throws -> WinampSkin? {
        let dir = Self.importedSkinsDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(sourceURL.lastPathComponent)

        // Source might be security-scoped (Files picker).
        let started = sourceURL.startAccessingSecurityScopedResource()
        defer { if started { sourceURL.stopAccessingSecurityScopedResource() } }

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)

        reload()
        return skins.first { !$0.isBundled && $0.id == dest }
    }

    func deleteImportedSkin(_ skin: WinampSkin) {
        guard !skin.isBundled else { return }
        try? FileManager.default.removeItem(at: skin.id)
        if activeSkin?.id == skin.id {
            activeSkin = skins.first
            if let s = activeSkin {
                UserDefaults.standard.set(s.displayName, forKey: activeSkinKey)
            }
        }
        reload()
    }

    // MARK: - Paths

    static func importedSkinsDirectory() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("HarmonIQ", isDirectory: true).appendingPathComponent("Skins", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
