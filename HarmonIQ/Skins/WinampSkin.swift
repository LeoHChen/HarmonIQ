import UIKit

/// An in-memory representation of a parsed Winamp 2.x skin (.wsz / .zip of BMPs + txt configs).
/// Sprite atlases are kept as `UIImage` (not pre-cropped) so the same atlas can be reused
/// to render different elements at draw time via `cgImage?.cropping(to:)`.
struct WinampSkin: Identifiable, Hashable {
    /// Identity is the source URL — bundled skins use a bundle URL, imported skins live
    /// at Application Support/HarmonIQ/Skins/<name>.wsz.
    let id: URL
    let displayName: String
    let isBundled: Bool

    // Sprite atlases (nil if the skin omits the file — most skins ship them all).
    let main: UIImage?
    let cButtons: UIImage?
    let titleBar: UIImage?
    let numbers: UIImage?
    let text: UIImage?
    let posBar: UIImage?
    let volume: UIImage?
    let balance: UIImage?
    let monoStereo: UIImage?
    let playPause: UIImage?
    let shufRep: UIImage?
    let eqMain: UIImage?
    let eqEx: UIImage?
    let plEdit: UIImage?

    /// Visualizer color palette — 24 RGB lines from VISCOLOR.TXT. Indexes 17–22 are bar
    /// height bands (bottom to top); 0 is background, 1 is grid, 23 is oscilloscope.
    let visColors: [UIColor]

    /// Playlist colors parsed from PLEDIT.TXT (INI-style).
    let playlistColors: PlaylistColors

    struct PlaylistColors: Hashable {
        var normal: UIColor = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
        var current: UIColor = .white
        var normalBG: UIColor = .black
        var selectedBG: UIColor = UIColor(red: 0, green: 0, blue: 0.6, alpha: 1)
        var font: String = "Arial"
    }

    /// Crop a sub-rectangle out of one of the sprite atlases.
    static func sprite(_ atlas: UIImage?, _ rect: CGRect) -> UIImage? {
        guard let atlas, let cg = atlas.cgImage else { return nil }
        // Skin BMPs are typically loaded with scale=1; cropping uses pixel coordinates.
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    /// Convenience for places where the rect is well-known and a missing atlas should
    /// fall through to a placeholder color in the caller.
    func sprite(_ atlas: KeyPath<WinampSkin, UIImage?>, rect: CGRect) -> UIImage? {
        Self.sprite(self[keyPath: atlas], rect)
    }
}
