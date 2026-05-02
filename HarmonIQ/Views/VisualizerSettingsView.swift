import SwiftUI

/// Settings → Visualizer picker. Lists every VisualizerStyle with a small live
/// preview canvas so the user can see what they'll get before selecting.
struct VisualizerSettingsView: View {
    @StateObject private var settings = VisualizerSettings.shared

    var body: some View {
        List {
            Section {
                ForEach(VisualizerStyle.allCases) { style in
                    Button {
                        settings.style = style
                    } label: {
                        StyleRow(style: style, isActive: settings.style == style)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Visualizer Style")
            } footer: {
                Text("In the now-playing view, double-tap or long-press the visualizer to cycle to the next style. Your choice persists across launches.")
            }
        }
        .navigationTitle("Visualizer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StyleRow: View {
    let style: VisualizerStyle
    let isActive: Bool
    // Each row owns its own engine so previews animate independently. Engine state
    // is small (a few float arrays) — eight rows worth is well within budget.
    @StateObject private var engine = VisualizerEngine()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(WinampTheme.lcdBackground)
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    Canvas { context, size in
                        // Synthesized signal so the preview moves without a real audio source.
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let pulse = Float(0.35 + 0.35 * sin(t * 2.4) + 0.15 * sin(t * 7.1))
                        let peak = Float(0.45 + 0.45 * sin(t * 3.1))
                        engine.advance(date: timeline.date,
                                       level: SIMD2<Float>(max(0, pulse), max(0, peak)),
                                       isPlaying: true)
                        switch style {
                        case .spectrum:     previewSpectrum(context: context, size: size, engine: engine)
                        case .oscilloscope: previewOscilloscope(context: context, size: size, engine: engine)
                        case .plasma:       previewPlasma(context: context, size: size, engine: engine)
                        case .mirror:       previewMirror(context: context, size: size, engine: engine)
                        case .circle:       previewCircle(context: context, size: size, engine: engine)
                        case .particles:    previewParticles(context: context, size: size, engine: engine)
                        case .fire:         previewFire(context: context, size: size, engine: engine)
                        case .starfield:    previewStarfield(context: context, size: size, engine: engine)
                        }
                    }
                }
            }
            .frame(width: 90, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(WinampTheme.bevelDark))

            VStack(alignment: .leading, spacing: 2) {
                Text(style.title.capitalized).font(.body)
                Text(blurb(for: style)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }

    private func blurb(for s: VisualizerStyle) -> String {
        switch s {
        case .spectrum:     return "Classic 24-band LED bars."
        case .oscilloscope: return "Glowing waveform trace."
        case .plasma:       return "Animated phosphor wash."
        case .mirror:       return "Spectrum reflected from the centerline."
        case .circle:       return "Bars radiate outward; ring pulses on beat."
        case .particles:    return "Phosphor sparks rise on transients."
        case .fire:         return "Heat-map columns rising from the bottom."
        case .starfield:    return "Stars accelerate toward the viewer."
        }
    }
}

// MARK: - Preview-only draw entry points
//
// Thin wrappers that re-implement the same look at thumbnail scale so the
// production hot path stays file-private to Visualizers.swift.

@MainActor
private func previewSpectrum(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    let bands = engine.bands
    let count = bands.count
    let gap: CGFloat = 1
    let totalGap = gap * CGFloat(count - 1)
    let barW = max(0.5, (size.width - totalGap) / CGFloat(count))
    let bottom = size.height
    for i in 0..<count {
        let h = CGFloat(bands[i]) * size.height
        guard h >= 0.5 else { continue }
        let x = CGFloat(i) * (barW + gap)
        let frac = h / size.height
        let color: Color = frac > 0.78 ? Color(red: 1, green: 0.35, blue: 0.35)
                          : frac > 0.55 ? Color(red: 1, green: 0.95, blue: 0.40)
                          : WinampTheme.lcdGlow
        context.fill(Path(CGRect(x: x, y: bottom - h, width: barW, height: h)), with: .color(color))
    }
}

@MainActor
private func previewOscilloscope(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    let samples = engine.oscilloscope
    guard samples.count > 1 else { return }
    let mid = size.height / 2
    var path = Path()
    for i in 0..<samples.count {
        let x = CGFloat(i) / CGFloat(samples.count - 1) * size.width
        let y = mid + CGFloat(samples[i]) * (size.height * 0.42)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    context.stroke(path, with: .color(WinampTheme.lcdGlow), lineWidth: 1.2)
}

@MainActor
private func previewPlasma(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    let cell: CGFloat = 4
    let cols = max(1, Int(size.width / cell) + 1)
    let rows = max(1, Int(size.height / cell) + 1)
    let phase = engine.phase
    for r in 0..<rows {
        for c in 0..<cols {
            let x = Double(c) / Double(cols)
            let y = Double(r) / Double(rows)
            let v = sin(x * 8 + phase) + sin(y * 6 - phase * 1.3) + sin((x + y) * 5 + phase * 0.7)
            let n = max(0, min(1, (v + 3) / 6))
            let color = Color(red: 0.05 + n * 0.4, green: 0.2 + n * 0.8, blue: 0.05 + n * 0.4)
            context.fill(Path(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)),
                         with: .color(color))
        }
    }
}

@MainActor
private func previewMirror(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    let bands = engine.bands
    let count = bands.count
    let gap: CGFloat = 1
    let totalGap = gap * CGFloat(count - 1)
    let barW = max(0.5, (size.width - totalGap) / CGFloat(count))
    let mid = size.height / 2
    for i in 0..<count {
        let h = CGFloat(bands[i]) * (size.height * 0.5)
        guard h >= 0.5 else { continue }
        let x = CGFloat(i) * (barW + gap)
        context.fill(Path(CGRect(x: x, y: mid - h, width: barW, height: h)), with: .color(WinampTheme.lcdGlow))
        context.fill(Path(CGRect(x: x, y: mid, width: barW, height: h)),
                     with: .color(WinampTheme.lcdGlow.opacity(0.6)))
    }
}

@MainActor
private func previewCircle(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    let bands = engine.bands
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let innerR = min(size.width, size.height) * 0.18
    let maxOuter = min(size.width, size.height) * 0.46
    let energy = bands.max() ?? 0
    let pulseR = innerR * (1.0 + CGFloat(energy) * 0.35)
    context.stroke(Path(ellipseIn: CGRect(x: center.x - pulseR, y: center.y - pulseR,
                                          width: pulseR * 2, height: pulseR * 2)),
                   with: .color(WinampTheme.lcdGlow), lineWidth: 1)
    let count = bands.count
    for i in 0..<count {
        let theta = Double(i) / Double(count) * 2 * .pi - .pi / 2
        let len = CGFloat(bands[i]) * (maxOuter - innerR)
        guard len >= 0.5 else { continue }
        var path = Path()
        let cosT = CGFloat(cos(theta)); let sinT = CGFloat(sin(theta))
        path.move(to: CGPoint(x: center.x + cosT * innerR, y: center.y + sinT * innerR))
        path.addLine(to: CGPoint(x: center.x + cosT * (innerR + len),
                                  y: center.y + sinT * (innerR + len)))
        context.stroke(path, with: .color(WinampTheme.lcdGlow), lineWidth: 1.2)
    }
}

@MainActor
private func previewParticles(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                 with: .color(WinampTheme.lcdGlow.opacity(0.4)))
    for p in engine.particles {
        guard p.life < p.maxLife, p.life >= 0 else { continue }
        let progress = p.life / p.maxLife
        let r: CGFloat = 1.0 + CGFloat(1.0 - progress) * 1.2
        let cx = CGFloat(p.x) * size.width
        let cy = CGFloat(p.y) * size.height
        context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                     with: .color(WinampTheme.lcdGlow.opacity(Double(1 - progress))))
    }
}

@MainActor
private func previewFire(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    let cols = VisualizerEngine.fireCols
    let rows = VisualizerEngine.fireRows
    let cellW = size.width / CGFloat(cols)
    let cellH = size.height / CGFloat(rows)
    for r in 0..<rows {
        let y = size.height - CGFloat(r + 1) * cellH
        for c in 0..<cols {
            let h = engine.fireHeat[r * cols + c]
            guard h > 0.05 else { continue }
            let color: Color = h < 0.25
                ? Color(red: Double(h * 2.4), green: 0, blue: 0)
                : h < 0.5
                ? Color(red: 1.0, green: Double((h - 0.25) * 2.0), blue: 0)
                : h < 0.75
                ? Color(red: 1.0, green: 0.5 + Double((h - 0.5) * 1.8), blue: Double((h - 0.5) * 0.8))
                : Color(red: 1.0, green: 0.95, blue: 0.2 + Double((h - 0.75) * 3.2))
            context.fill(Path(CGRect(x: CGFloat(c) * cellW, y: y, width: cellW + 0.5, height: cellH + 0.5)),
                         with: .color(color))
        }
    }
}

@MainActor
private func previewStarfield(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    let cx = size.width / 2
    let cy = size.height / 2
    let scale = min(size.width, size.height) * 0.8
    for s in engine.stars {
        let sx = cx + CGFloat(s.x / s.z) * scale * 0.5
        let sy = cy + CGFloat(s.y / s.z) * scale * 0.5
        guard sx >= -2, sx <= size.width + 2, sy >= -2, sy <= size.height + 2 else { continue }
        let depth = max(0.05, min(1.0, s.z))
        let radius: CGFloat = max(0.4, CGFloat(1.0 - depth) * 1.8)
        let alpha = 1.0 - Double(depth) * 0.85
        context.fill(Path(ellipseIn: CGRect(x: sx - radius, y: sy - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: .color(WinampTheme.lcdGlow.opacity(alpha)))
    }
}
