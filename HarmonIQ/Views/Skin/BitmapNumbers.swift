import SwiftUI
import UIKit

/// Renders the time display (M:SS or MM:SS) using the active skin's NUMBERS.BMP atlas.
/// Each digit is a 9×13 source cell; a colon-like gap is drawn from a single column of
/// pixels in the atlas. We don't try to be clever — we just draw 4 digits with a
/// 5-pixel gap between minutes and seconds.
struct BitmapTime: View {
    let seconds: TimeInterval
    var pixelSize: CGFloat = 2
    @EnvironmentObject var skinManager: SkinManager

    var body: some View {
        let parts = digits(for: seconds)
        Canvas(rendersAsynchronously: false) { ctx, _ in
            guard let atlas = skinManager.activeSkin?.numbers, let cg = atlas.cgImage else { return }
            let w = SkinFormat.LCDDigit.cellSize.width * pixelSize
            let h = SkinFormat.LCDDigit.cellSize.height * pixelSize
            // Layout: D D <gap=5> D D
            var x: CGFloat = 0
            for (i, d) in parts.enumerated() {
                if i == 2 { x += 5 * pixelSize }  // colon gap between MM and SS
                let src = SkinFormat.LCDDigit.rect(for: d)
                if let cropped = cg.cropping(to: src) {
                    ctx.draw(Image(decorative: cropped, scale: 1, orientation: .up).interpolation(.none),
                             in: CGRect(x: x, y: 0, width: w, height: h))
                }
                x += w
            }
        }
        .frame(width: 4 * SkinFormat.LCDDigit.cellSize.width * pixelSize + 5 * pixelSize,
               height: SkinFormat.LCDDigit.cellSize.height * pixelSize)
    }

    private func digits(for t: TimeInterval) -> [Int] {
        guard t.isFinite, t >= 0 else { return [0, 0, 0, 0] }
        let total = Int(t.rounded(.down))
        let m = min(99, total / 60)
        let s = total % 60
        return [m / 10, m % 10, s / 10, s % 10]
    }
}
