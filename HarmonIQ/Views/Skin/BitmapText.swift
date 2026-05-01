import SwiftUI
import UIKit

/// Renders a string using the active skin's TEXT.BMP bitmap font (5×6 glyphs in a 31-col grid).
/// Unknown characters render as blank cells.
struct BitmapText: View {
    let text: String
    var pixelSize: CGFloat = 2  // each source pixel becomes pixelSize CGPoints
    @EnvironmentObject var skinManager: SkinManager

    var body: some View {
        let glyphs = mapped(text)
        Canvas(rendersAsynchronously: false) { ctx, _ in
            guard let atlas = skinManager.activeSkin?.text, let cg = atlas.cgImage else { return }
            let cell = SkinFormat.BitmapFont.cellSize
            let cellW = cell.width * pixelSize
            let cellH = cell.height * pixelSize
            for (i, rect) in glyphs.enumerated() {
                guard let glyph = cg.cropping(to: rect) else { continue }
                let dest = CGRect(x: CGFloat(i) * cellW, y: 0, width: cellW, height: cellH)
                ctx.draw(Image(decorative: glyph, scale: 1, orientation: .up).interpolation(.none),
                         in: dest)
            }
        }
        .frame(width: CGFloat(glyphs.count) * SkinFormat.BitmapFont.cellSize.width * pixelSize,
               height: SkinFormat.BitmapFont.cellSize.height * pixelSize)
    }

    /// Map characters to source rectangles in TEXT.BMP. Webamp's canonical mapping —
    /// row 0 is uppercase + " + @ + spaces, row 1 is digits + punctuation.
    private func mapped(_ s: String) -> [CGRect] {
        s.uppercased().map { char in
            BitmapText.glyphRect(for: char)
        }
    }

    static func glyphRect(for c: Character) -> CGRect {
        // Returns the 5×6 source rect inside text.bmp for the given character. Blank
        // (empty) rect for chars not in the charset.
        let row0 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\"@  "
        let row1 = "0123456789…:.;-=÷ \\\"#$%&!'+*?,/_()"
        if let i = row0.firstIndex(of: c) {
            let col = row0.distance(from: row0.startIndex, to: i)
            return CGRect(x: CGFloat(col) * 5, y: 0, width: 5, height: 6)
        }
        if let i = row1.firstIndex(of: c) {
            let col = row1.distance(from: row1.startIndex, to: i)
            return CGRect(x: CGFloat(col) * 5, y: 6, width: 5, height: 6)
        }
        // Space / unknown → far-right of row 0 (always blank in canonical skins).
        return CGRect(x: 30 * 5, y: 0, width: 5, height: 6)
    }
}
