import Foundation
import UIKit
import ZIPFoundation

enum SkinLoaderError: Error {
    case openFailed
    case missingMain
}

/// Loads a Winamp .wsz (zip of BMPs + txt configs) into a `WinampSkin`. Tolerant of
/// case differences and missing optional sprites — only `main.bmp` is required.
enum SkinLoader {

    /// Load the skin at the given URL. Caller is responsible for security-scoped access
    /// if the URL points outside the app sandbox.
    static func load(from url: URL, isBundled: Bool) throws -> WinampSkin {
        guard let archive = try? Archive(url: url, accessMode: .read) else {
            throw SkinLoaderError.openFailed
        }

        // Build a case-insensitive map filename → entry.
        var entries: [String: Entry] = [:]
        for entry in archive {
            let key = (entry.path as NSString).lastPathComponent.lowercased()
            entries[key] = entry
        }

        func bytes(_ name: String) -> Data? {
            guard let entry = entries[name.lowercased()] else { return nil }
            var data = Data()
            _ = try? archive.extract(entry) { data.append($0) }
            return data
        }

        func image(_ name: String) -> UIImage? {
            guard let data = bytes(name) else { return nil }
            return UIImage(data: data)
        }

        // numbers.bmp is the classic 99×13; nums_ex.bmp is the extended 108×13 with minus.
        let numbers = image("numbers.bmp") ?? image("nums_ex.bmp")
        guard let main = image("main.bmp") else { throw SkinLoaderError.missingMain }

        let visColors = parseVisColors(bytes("viscolor.txt"))
        let plColors = parsePlaylistColors(bytes("pledit.txt"))

        let displayName = url.deletingPathExtension().lastPathComponent

        return WinampSkin(
            id: url,
            displayName: displayName,
            isBundled: isBundled,
            main: main,
            cButtons: image("cbuttons.bmp"),
            titleBar: image("titlebar.bmp"),
            numbers: numbers,
            text: image("text.bmp"),
            posBar: image("posbar.bmp"),
            volume: image("volume.bmp"),
            balance: image("balance.bmp"),
            monoStereo: image("monoster.bmp"),
            playPause: image("playpaus.bmp"),
            shufRep: image("shufrep.bmp"),
            eqMain: image("eqmain.bmp"),
            eqEx: image("eq_ex.bmp"),
            plEdit: image("pledit.bmp"),
            visColors: visColors,
            playlistColors: plColors
        )
    }

    // MARK: - viscolor.txt

    /// Parse the 24-line "R,G,B" palette. Lines are decimal 0–255; comments/garbage
    /// after the third number are ignored.
    static func parseVisColors(_ data: Data?) -> [UIColor] {
        guard let data, let text = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .isoLatin1) else {
            return defaultVisColors
        }
        var result: [UIColor] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") { continue }
            // Take the first 3 comma-separated integers; allow ", " or ","
            let parts = trimmed.split(whereSeparator: { ",;\t ".contains($0) })
                .compactMap { Int($0) }
            guard parts.count >= 3 else { continue }
            let r = CGFloat(min(255, max(0, parts[0]))) / 255
            let g = CGFloat(min(255, max(0, parts[1]))) / 255
            let b = CGFloat(min(255, max(0, parts[2]))) / 255
            result.append(UIColor(red: r, green: g, blue: b, alpha: 1))
            if result.count == 24 { break }
        }
        if result.count < 24 {
            // Pad with last color (or default) so callers can index 0..23 safely.
            let pad = result.last ?? UIColor.green
            result.append(contentsOf: Array(repeating: pad, count: 24 - result.count))
        }
        return result
    }

    private static let defaultVisColors: [UIColor] = (0..<24).map { i in
        let g = CGFloat(40 + i * 9) / 255.0
        return UIColor(red: 0, green: g, blue: 0, alpha: 1)
    }

    // MARK: - pledit.txt

    static func parsePlaylistColors(_ data: Data?) -> WinampSkin.PlaylistColors {
        var pc = WinampSkin.PlaylistColors()
        guard let data, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return pc
        }
        for line in text.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard let eq = l.firstIndex(of: "=") else { continue }
            let key = l[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = l[l.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "normal":     if let c = parseHex(value) { pc.normal = c }
            case "current":    if let c = parseHex(value) { pc.current = c }
            case "normalbg":   if let c = parseHex(value) { pc.normalBG = c }
            case "selectedbg": if let c = parseHex(value) { pc.selectedBG = c }
            case "font":       pc.font = value
            default: break
            }
        }
        return pc
    }

    private static func parseHex(_ s: String) -> UIColor? {
        var hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        hex = hex.uppercased()
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}
