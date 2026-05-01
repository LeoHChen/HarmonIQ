import SwiftUI
import UIKit

/// A skinned spectrum visualizer that draws into the canonical 76×16 visualizer area
/// using the active skin's VISCOLOR.TXT palette. Reuses VisualizerEngine for the
/// synthesized band data so this is a drop-in render layer on top of the existing engine.
struct SkinnedVisualizer: View {
    @ObservedObject var engine: VisualizerEngine
    var pixelSize: CGFloat = 2
    @EnvironmentObject var skinManager: SkinManager
    @EnvironmentObject var player: AudioPlayerManager

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas(rendersAsynchronously: false) { ctx, size in
                engine.advance(date: timeline.date, level: player.levels, isPlaying: player.isPlaying)
                draw(into: ctx, size: size)
            }
        }
        .frame(width: 76 * pixelSize, height: 16 * pixelSize)
    }

    private func draw(into ctx: GraphicsContext, size: CGSize) {
        let palette = skinManager.activeSkin?.visColors ?? defaultPalette()
        // Background (index 0).
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(palette[0])))

        // 19 bars across 76px → 4px per bar (skin-space). Use 19 bars to fit cleanly.
        let bars = 19
        let barW = size.width / CGFloat(bars)
        let bands = engine.bands
        // engine has 24 bands; resample to `bars`.
        for i in 0..<bars {
            let f = Float(i) / Float(bars - 1)
            let srcIdx = min(bands.count - 1, Int(f * Float(bands.count - 1) + 0.5))
            let h = max(0.05, CGFloat(bands[srcIdx]))
            let pixelHeight = h * size.height
            let x = CGFloat(i) * barW
            // Draw from bottom up using the skin's bar gradient (palette[2..17] = 16 levels).
            // We draw one rect per pixel-row (pixelSize tall in screen units) so each
            // row picks the matching color.
            let rowH: CGFloat = pixelSize
            var y = size.height
            var drawn: CGFloat = 0
            while drawn < pixelHeight - 0.5 {
                let frac = drawn / size.height
                let levelIdx = 17 - min(15, Int(frac * 15))   // top of bar = palette[2], bottom = palette[17]
                let color = palette[max(2, min(17, levelIdx))]
                let rect = CGRect(x: x + 0.5, y: y - rowH, width: barW - 1, height: rowH)
                ctx.fill(Path(rect), with: .color(Color(color)))
                y -= rowH
                drawn += rowH
            }
        }
    }

    private func defaultPalette() -> [UIColor] {
        // Phosphor green fallback when no skin is loaded.
        (0..<24).map { i in UIColor(red: 0, green: CGFloat(40 + i * 9) / 255.0, blue: 0, alpha: 1) }
    }
}
