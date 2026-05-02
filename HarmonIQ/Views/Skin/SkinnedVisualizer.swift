import SwiftUI
import UIKit

/// A skinned visualizer that draws into the canonical 76×16 visualizer area
/// using the active skin's VISCOLOR.TXT palette. Reuses VisualizerEngine for
/// the synthesized state and shares `VisualizerSettings.style` with the
/// SwiftUI player so cycling stays unified across both UIs — tap the rect to
/// advance through the 8 styles.
///
/// Some `VisualizerStyle` cases (plasma, circle) don't fit the Winamp pixel-grid
/// + 24-color palette — those fall back to the spectrum bar render so the
/// skinned player still has *something* sensible to show.
struct SkinnedVisualizer: View {
    @ObservedObject var engine: VisualizerEngine
    var pixelSize: CGFloat = 2
    @EnvironmentObject var skinManager: SkinManager
    @EnvironmentObject var player: AudioPlayerManager
    @StateObject private var settings = VisualizerSettings.shared

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

        switch settings.style {
        case .spectrum, .plasma, .circle:
            // plasma/circle don't translate to the 76×16 + palette aesthetic — fall back to bars.
            drawSpectrumBars(ctx: ctx, size: size, colors: colors)
        case .oscilloscope,
             .oscGlow, .oscMultiLayer, .oscMirror, .oscFill,
             .oscRadial, .oscWaterfall, .oscLissajous, .oscBeat:
            // The fancy oscilloscope variants (issue #27) lean on SwiftUI Canvas
            // filters/blur which don't translate to the chunky 24-color palette
            // grid. Fall back to the canonical Winamp scope line for all of them.
            drawOscilloscope(ctx: ctx, size: size, colors: colors)
        case .mirror:
            drawMirrorBars(ctx: ctx, size: size, colors: colors)
        case .particles:
            drawParticles(ctx: ctx, size: size, colors: colors)
        case .fire:
            drawFire(ctx: ctx, size: size, colors: colors)
        case .starfield:
            drawStarfield(ctx: ctx, size: size, colors: colors)
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

    private func drawMirrorBars(ctx: GraphicsContext, size: CGSize, colors: [Color]) {
        let bars = 19
        let barW = size.width / CGFloat(bars)
        let bands = engine.bands
        let mid = size.height / 2
        // Center reference line in the grid color (palette[1] when present).
        let refColor = colors.indices.contains(1) ? colors[1].opacity(0.6) : colors[2].opacity(0.4)
        ctx.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: max(1, pixelSize * 0.5))),
                 with: .color(refColor))
        for i in 0..<bars {
            let f = Float(i) / Float(bars - 1)
            let srcIdx = min(bands.count - 1, Int(f * Float(bands.count - 1) + 0.5))
            let halfH = CGFloat(bands[srcIdx]) * (size.height * 0.5)
            guard halfH >= pixelSize else { continue }
            let x = CGFloat(i) * barW
            let rowH = pixelSize
            // Top half — draw upward from the centerline.
            var y = mid
            var drawn: CGFloat = 0
            while drawn < halfH - 0.5 {
                let frac = drawn / (size.height * 0.5)
                let levelIdx = 17 - min(15, Int(frac * 15))
                let color = colors[max(2, min(17, levelIdx))]
                ctx.fill(Path(CGRect(x: x + 0.5, y: y - rowH, width: barW - 1, height: rowH)),
                         with: .color(color))
                ctx.fill(Path(CGRect(x: x + 0.5, y: 2 * mid - y, width: barW - 1, height: rowH)),
                         with: .color(color.opacity(0.7)))
                y -= rowH
                drawn += rowH
            }
        }
    }

    private func drawParticles(ctx: GraphicsContext, size: CGSize, colors: [Color]) {
        // Floor line in the brightest base color.
        let floorColor = colors[max(2, min(17, 8))]
        ctx.fill(Path(CGRect(x: 0, y: size.height - pixelSize, width: size.width, height: pixelSize)),
                 with: .color(floorColor.opacity(0.5)))
        // Each particle = one skin pixel block. Color picks from the spectrum palette
        // ramp by life — fresh = top (hot), old = mid.
        for p in engine.particles {
            guard p.life < p.maxLife, p.life >= 0 else { continue }
            let progress = p.life / p.maxLife
            let xPx = (CGFloat(p.x) * size.width / pixelSize).rounded() * pixelSize
            let yPx = (CGFloat(p.y) * size.height / pixelSize).rounded() * pixelSize
            // Map life [0,1] → palette index [17 (hot) down to 6 (cool)].
            let idx = 17 - Int(progress * 11)
            let color = colors[max(2, min(17, idx))].opacity(Double(1 - progress))
            ctx.fill(Path(CGRect(x: xPx, y: yPx, width: pixelSize, height: pixelSize)),
                     with: .color(color))
        }
    }

    private func drawFire(ctx: GraphicsContext, size: CGSize, colors: [Color]) {
        // Sample the engine's heat grid (20×14) into the 76×16 skin grid.
        // The skin's spectrum palette already runs cool→hot bottom-to-top,
        // so we map heat directly onto palette indices 2…17.
        let cols = 76
        let rows = 16
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)
        let srcCols = VisualizerEngine.fireCols
        let srcRows = VisualizerEngine.fireRows
        for r in 0..<rows {
            // y=0 in the grid is the bottom (hottest) row.
            let srcR = min(srcRows - 1, Int(Float(r) / Float(rows) * Float(srcRows)))
            let yPx = size.height - CGFloat(r + 1) * cellH
            for c in 0..<cols {
                let srcC = min(srcCols - 1, Int(Float(c) / Float(cols) * Float(srcCols)))
                let h = engine.fireHeat[srcR * srcCols + srcC]
                guard h > 0.06 else { continue }
                // h ∈ [0,1] → palette index [2 (cool) … 17 (hot)].
                let idx = 2 + Int(h * 15)
                let color = colors[max(2, min(17, idx))]
                ctx.fill(Path(CGRect(x: CGFloat(c) * cellW, y: yPx,
                                     width: cellW + 0.5, height: cellH + 0.5)),
                         with: .color(color))
            }
        }
    }

    private func drawStarfield(ctx: GraphicsContext, size: CGSize, colors: [Color]) {
        // White-ish "star" color: prefer palette[18] (oscilloscope), fall back to palette[17] (peak).
        let starColor = colors.indices.contains(18) ? colors[18] : colors[17]
        let cx = size.width / 2
        let cy = size.height / 2
        let scale = min(size.width, size.height) * 0.8
        for s in engine.stars {
            let sxRaw = cx + CGFloat(s.x / s.z) * scale * 0.5
            let syRaw = cy + CGFloat(s.y / s.z) * scale * 0.5
            guard sxRaw >= 0, sxRaw < size.width, syRaw >= 0, syRaw < size.height else { continue }
            // Snap to the skin-pixel grid.
            let xPx = (sxRaw / pixelSize).floor() * pixelSize
            let yPx = (syRaw / pixelSize).floor() * pixelSize
            let depth = max(0.05, min(1.0, s.z))
            let alpha = 1.0 - Double(depth) * 0.8
            ctx.fill(Path(CGRect(x: xPx, y: yPx, width: pixelSize, height: pixelSize)),
                     with: .color(starColor.opacity(alpha)))
        }
    }

    private func defaultPalette() -> [UIColor] {
        (0..<24).map { i in UIColor(red: 0, green: CGFloat(40 + i * 9) / 255.0, blue: 0, alpha: 1) }
    }
}

// MARK: - small helpers

private extension CGFloat {
    func floor() -> CGFloat { rounded(.down) }
}
