import SwiftUI
import UIKit

/// A skinned visualizer that draws into the canonical 76×16 visualizer area
/// using the active skin's VISCOLOR.TXT palette. Follows the authentic Winamp
/// 3-mode cycle (spectrum → oscilloscope → off) — tap the rect to advance.
struct SkinnedVisualizer: View {
    @ObservedObject var engine: VisualizerEngine
    var pixelSize: CGFloat = 2
    @EnvironmentObject var skinManager: SkinManager
    @EnvironmentObject var player: AudioPlayerManager
    @StateObject private var settings = SkinnedVisualizerSettings.shared

    // Cache the resolved SwiftUI Color array so we don't convert UIColor → Color
    // on every frame. Invalidated when the active skin changes.
    @State private var cachedSkinID: String? = nil
    @State private var cachedColors: [Color] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas(rendersAsynchronously: false) { ctx, size in
                engine.advance(date: timeline.date, level: player.levels, isPlaying: player.isPlaying)
                draw(into: ctx, size: size)
            }
        }
        .frame(width: 76 * pixelSize, height: 16 * pixelSize)
        .contentShape(Rectangle())
        .onTapGesture { settings.cycle() }
    }

    private func resolvedColors() -> [Color] {
        let skinID = skinManager.activeSkin?.id.path
        if skinID == cachedSkinID { return cachedColors }
        let palette = skinManager.activeSkin?.visColors ?? defaultPalette()
        let colors = palette.map { Color($0) }
        // SwiftUI Canvas closures are @MainActor — state writes are fine here
        // because Canvas calls are synchronous on the main thread.
        DispatchQueue.main.async {
            cachedSkinID = skinID
            cachedColors = colors
        }
        return colors
    }

    private func draw(into ctx: GraphicsContext, size: CGSize) {
        let colors = resolvedColors()
        guard colors.count >= 18 else { return }

        // Background (palette index 0).
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(colors[0]))

        switch settings.mode {
        case .spectrum:
            drawSpectrumBars(ctx: ctx, size: size, colors: colors)
        case .oscilloscope:
            drawOscilloscope(ctx: ctx, size: size, colors: colors)
        case .off:
            // Background fill above already painted palette index 0; nothing else to draw.
            break
        }
    }

    // MARK: - Style renderers
    //
    // All renderers think in skin-pixel units (76×16), then multiply by
    // `pixelSize` for actual on-screen geometry.

    private func drawSpectrumBars(ctx: GraphicsContext, size: CGSize, colors: [Color]) {
        // 19 bars across 76px → 4px per bar (skin-space). Use 19 bars to fit cleanly.
        let bars = 19
        let barW = size.width / CGFloat(bars)
        let bands = engine.bands
        for i in 0..<bars {
            let f = Float(i) / Float(bars - 1)
            let srcIdx = min(bands.count - 1, Int(f * Float(bands.count - 1) + 0.5))
            let pixelHeight = CGFloat(bands[srcIdx]) * size.height
            guard pixelHeight >= pixelSize else { continue }
            let x = CGFloat(i) * barW
            let rowH: CGFloat = pixelSize
            var y = size.height
            var drawn: CGFloat = 0
            while drawn < pixelHeight - 0.5 {
                let frac = drawn / size.height
                let levelIdx = 17 - min(15, Int(frac * 15))
                let rect = CGRect(x: x + 0.5, y: y - rowH, width: barW - 1, height: rowH)
                ctx.fill(Path(rect), with: .color(colors[max(2, min(17, levelIdx))]))
                y -= rowH
                drawn += rowH
            }
        }
    }

    /// Oscilloscope using palette index 18 (the canonical VISCOLOR oscilloscope color).
    /// Renders on the skin-pixel grid so it keeps a chunky CRT look at small pixelSize.
    private func drawOscilloscope(ctx: GraphicsContext, size: CGSize, colors: [Color]) {
        let lineColor = colors.indices.contains(18) ? colors[18] : colors[17]
        // 76 columns of skin pixels — sample one oscilloscope value per column.
        let cols = 76
        let samples = engine.oscilloscope
        guard samples.count > 1 else { return }
        let mid = size.height / 2
        let amp = size.height * 0.42

        var prevY: CGFloat = mid
        for c in 0..<cols {
            let t = Float(c) / Float(cols - 1)
            let srcIdx = Int(t * Float(samples.count - 1))
            let y = mid + CGFloat(samples[srcIdx]) * amp
            // Clamp + snap to skin-pixel rows.
            let snapped = (y / pixelSize).rounded() * pixelSize
            let xPx = CGFloat(c) * pixelSize
            // Draw a vertical span connecting prevY → snapped so the line stays continuous
            // even when adjacent samples diverge.
            let yTop = min(prevY, snapped)
            let yBot = max(prevY, snapped)
            ctx.fill(Path(CGRect(x: xPx, y: yTop, width: pixelSize, height: max(pixelSize, yBot - yTop))),
                     with: .color(lineColor))
            prevY = snapped
        }
    }

    private func defaultPalette() -> [UIColor] {
        (0..<24).map { i in UIColor(red: 0, green: CGFloat(40 + i * 9) / 255.0, blue: 0, alpha: 1) }
    }
}
