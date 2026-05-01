import Foundation
import AVFoundation
import UIKit

struct ExtractedMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var discNumber: Int?
    var duration: TimeInterval = 0
    var artworkData: Data?
}

enum MetadataExtractor {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "flac", "wav", "aiff", "aif", "aac"]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func extract(from url: URL) async -> ExtractedMetadata {
        var result = ExtractedMetadata()
        let asset = AVURLAsset(url: url)

        // Duration
        do {
            let duration = try await asset.load(.duration)
            result.duration = CMTimeGetSeconds(duration)
            if !result.duration.isFinite { result.duration = 0 }
        } catch {
            result.duration = 0
        }

        // Common metadata
        do {
            let common = try await asset.load(.commonMetadata)
            for item in common {
                guard let key = item.commonKey?.rawValue else { continue }
                switch key {
                case AVMetadataKey.commonKeyTitle.rawValue:
                    if let v = try? await item.load(.stringValue) { result.title = v }
                case AVMetadataKey.commonKeyArtist.rawValue:
                    if let v = try? await item.load(.stringValue) { result.artist = v }
                case AVMetadataKey.commonKeyAlbumName.rawValue:
                    if let v = try? await item.load(.stringValue) { result.album = v }
                case AVMetadataKey.commonKeyArtwork.rawValue:
                    if let data = try? await item.load(.dataValue) { result.artworkData = data }
                case AVMetadataKey.commonKeyType.rawValue:
                    if let v = try? await item.load(.stringValue) { result.genre = v }
                default:
                    break
                }
            }
        } catch {
            // ignore
        }

        // Format-specific metadata
        do {
            let formats = try await asset.load(.availableMetadataFormats)
            for format in formats {
                let items: [AVMetadataItem]
                do {
                    items = try await asset.loadMetadata(for: format)
                } catch {
                    continue
                }
                for item in items {
                    let keyString = item.identifier?.rawValue ?? (item.key as? String ?? "")
                    let lowered = keyString.lowercased()
                    let stringValue = (try? await item.load(.stringValue))
                    let numberValue = (try? await item.load(.numberValue))

                    if lowered.contains("albumartist") || lowered.contains("aart") || lowered.contains("tpe2") {
                        if let v = stringValue, result.albumArtist == nil { result.albumArtist = v }
                    } else if lowered.contains("genre") || lowered.contains("tcon") || lowered.hasSuffix("/gnre") {
                        if let v = stringValue, result.genre == nil { result.genre = v }
                    } else if lowered.contains("year") || lowered.contains("tyer") || lowered.contains("tdrc") || lowered.contains("/day") {
                        if let v = stringValue, let y = Int(v.prefix(4)) { result.year = y }
                        if result.year == nil, let n = numberValue { result.year = n.intValue }
                    } else if lowered.contains("tracknumber") || lowered.contains("trkn") || lowered.contains("trck") {
                        if let v = stringValue {
                            let parts = v.split(separator: "/")
                            if let first = parts.first, let n = Int(first) { result.trackNumber = n }
                        } else if let n = numberValue {
                            result.trackNumber = n.intValue
                        }
                    } else if lowered.contains("discnumber") || lowered.contains("disk") || lowered.contains("tpos") {
                        if let v = stringValue {
                            let parts = v.split(separator: "/")
                            if let first = parts.first, let n = Int(first) { result.discNumber = n }
                        } else if let n = numberValue {
                            result.discNumber = n.intValue
                        }
                    } else if lowered.contains("title") || lowered.contains("tit2") {
                        if let v = stringValue, result.title == nil { result.title = v }
                    } else if lowered.contains("artist") || lowered.contains("tpe1") {
                        if let v = stringValue, result.artist == nil { result.artist = v }
                    } else if lowered.contains("album") || lowered.contains("talb") {
                        if let v = stringValue, result.album == nil { result.album = v }
                    } else if lowered.contains("artwork") || lowered.contains("apic") || lowered.contains("covr") {
                        if let data = try? await item.load(.dataValue), result.artworkData == nil { result.artworkData = data }
                    }
                }
            }
        } catch {
            // ignore
        }

        return result
    }

    static func saveArtwork(_ data: Data, named name: String, to directory: URL) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let target = CGSize(width: 600, height: 600)
        let resized = image.resized(maxDimension: max(target.width, target.height))
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let url = directory.appendingPathComponent("\(name).jpg")
        do {
            try jpeg.write(to: url, options: .atomic)
            return url.lastPathComponent
        } catch {
            return nil
        }
    }

    /// Async wrapper so callers from non-MainActor contexts can save artwork without UIKit isolation issues.
    static func saveArtworkAsync(_ data: Data, named name: String, to directory: URL) async -> String? {
        await Task.detached(priority: .utility) {
            saveArtwork(data, named: name, to: directory)
        }.value
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
