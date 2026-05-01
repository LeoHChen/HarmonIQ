import SwiftUI

enum VisualizerMode: String, CaseIterable, Identifiable {
    case spectrum
    case oscilloscope
    case plasma

    var id: String { rawValue }
    var title: String {
        switch self {
        case .spectrum:     return "SPECTRUM"
        case .oscilloscope: return "OSCILLOSCOPE"
        case .plasma:       return "PLASMA"
        }
    }
    var icon: String {
        switch self {
        case .spectrum:     return "chart.bar.fill"
        case .oscilloscope: return "waveform.path"
        case .plasma:       return "flame.fill"
        }
    }
}

/// Container that sits in NowPlayingView. Uses a TimelineView so we redraw at ~30Hz
/// regardless of @Published throttling, and reads the latest level from the player.
struct VisualizerView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @State private var mode: VisualizerMode = .spectrum
    @StateObject private var engine = VisualizerEngine()

    var body: some View {
        VStack(spacing: 6) {
            // Header bar — clickable mode switcher
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WinampTheme.lcdGlow)
                Text("VIS · \(mode.title)")
                    .font(WinampTheme.lcdFont(size: 10))
                    .foregroundStyle(WinampTheme.lcdGlow)
                Spacer()
                ForEach(VisualizerMode.allCases) { m in
                    Button {
                        mode = m
                    } label: {
                        Image(systemName: m.icon)
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 22, height: 16)
                            .foregroundStyle(m == mode ? WinampTheme.lcdGlow : WinampTheme.lcdDim)
                            .background(m == mode ? WinampTheme.lcdGlow.opacity(0.12) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(WinampTheme.bevelDark))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(WinampTheme.lcdBackground)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(WinampTheme.bevelDark))
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // Visualizer surface
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    engine.advance(date: timeline.date, level: player.levels, isPlaying: player.isPlaying)
                    drawScanlines(context: context, size: size)
                    switch mode {
                    case .spectrum:
                        drawSpectrum(context: context, size: size, engine: engine)
                    case .oscilloscope:
                        drawOscilloscope(context: context, size: size, engine: engine)
                    case .plasma:
                        drawPlasma(context: context, size: size, engine: engine)
                    }
                    drawCRTBezel(context: context, size: size)
                }
            }
            .background(WinampTheme.lcdBackground)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(WinampTheme.bevelDark))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .bevelPanel(corner: 6)
    }
}

// MARK: - Engine

@MainActor
final class VisualizerEngine: ObservableObject {
    /// 24 spectrum bands. Synthesized from the player's avg + peak by emphasizing different
    /// regions of the band space at different times — gives a believable spectrum from a single value.
    private(set) var bands: [Float] = Array(repeating: 0, count: 24)
    private(set) var bandPeaks: [Float] = Array(repeating: 0, count: 24)
    /// 128-sample oscilloscope buffer.
    private(set) var oscilloscope: [Float] = Array(repeating: 0, count: 128)
    /// Drives the plasma's animated phase.
    private(set) var phase: Double = 0

    private var lastDate: Date = .distantPast
    private var frameCount: UInt64 = 0
    private var rng = SystemRandomNumberGenerator()

    func advance(date: Date, level: SIMD2<Float>, isPlaying: Bool) {
        let dt = max(0, min(0.1, date.timeIntervalSince(lastDate)))
        lastDate = date
        frameCount &+= 1

        let avg = level.x
        let peak = level.y
        let energy = max(avg, peak * 0.7)

        // --- Spectrum: imagine 24 bands. Bass leans on avg, treble leans on peak transients.
        for i in 0..<bands.count {
            let t = Float(i) / Float(bands.count - 1)
            // shape of band response — bell curves moving over time
            let phaseShift = Float(frameCount) * 0.02
            let bell1 = expf(-powf((t - 0.2 + sinf(phaseShift) * 0.05) * 4.5, 2))
            let bell2 = expf(-powf((t - 0.55 + sinf(phaseShift * 1.7) * 0.07) * 4.5, 2))
            let bell3 = expf(-powf((t - 0.85 + cosf(phaseShift * 0.9) * 0.04) * 5.0, 2))
            let bandEnergy = energy * (1.05 - t * 0.3)        // gentle slope down
            let scatter = Float.random(in: 0.85...1.15, using: &rng)
            let target = min(1.0, bandEnergy * (bell1 * 1.0 + bell2 * 0.8 + bell3 * 0.6) * scatter)
            // smooth toward target
            let smoothing: Float = isPlaying ? 0.55 : 0.2
            bands[i] = bands[i] * (1 - smoothing) + target * smoothing
            // peak markers fall slowly
            if bands[i] > bandPeaks[i] {
                bandPeaks[i] = bands[i]
            } else {
                bandPeaks[i] = max(0, bandPeaks[i] - Float(dt) * 0.6)
            }
        }

        // --- Oscilloscope: synthesize a wave whose amplitude tracks the level, with noise.
        let ampl = isPlaying ? max(0.05, energy) : 0.0
        let baseFreq: Float = 6.0 + energy * 18.0
        for i in 0..<oscilloscope.count {
            let x = Float(i) / Float(oscilloscope.count) * 2 * .pi
            let phaseF = Float(frameCount) * 0.18
            let wave = sinf(x * baseFreq + phaseF) * 0.65
                    + sinf(x * baseFreq * 0.5 + phaseF * 0.7) * 0.25
                    + Float.random(in: -0.08...0.08, using: &rng)
            oscilloscope[i] = wave * ampl
        }

        // --- Plasma: just advance time, faster when audio is loud.
        phase += dt * (0.4 + Double(energy) * 2.6)
    }
}

// MARK: - Drawing

private func drawScanlines(context: GraphicsContext, size: CGSize) {
    let lineH: CGFloat = 2
    var y: CGFloat = 0
    let color = Color.white.opacity(0.04)
    while y < size.height {
        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(color))
        y += lineH
    }
}

private func drawCRTBezel(context: GraphicsContext, size: CGSize) {
    var ctx = context
    // subtle inner glow
    ctx.addFilter(.blur(radius: 0.8))
    let rect = CGRect(origin: .zero, size: size)
    let path = Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 3)
    ctx.stroke(path, with: .color(WinampTheme.lcdGlow.opacity(0.2)), lineWidth: 1)
}

@MainActor
private func drawSpectrum(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    let bands = engine.bands
    let peaks = engine.bandPeaks
    let count = bands.count
    let gap: CGFloat = 2
    let totalGap = gap * CGFloat(count - 1)
    let barW = max(1, (size.width - totalGap) / CGFloat(count))
    let bottom = size.height

    for i in 0..<count {
        let h = CGFloat(bands[i]) * size.height
        let x = CGFloat(i) * (barW + gap)
        // segmented LED look — break the bar into rows
        let segH: CGFloat = 4
        var y = bottom
        var drawn: CGFloat = 0
        while drawn < h - 1 {
            let rowH = min(segH - 1, h - drawn)
            let rect = CGRect(x: x, y: y - rowH, width: barW, height: rowH)
            // color band: green low, yellow mid, red high
            let frac = (bottom - y + rowH) / size.height
            let color: Color = {
                if frac > 0.78 { return Color(red: 1, green: 0.35, blue: 0.35) }
                if frac > 0.55 { return Color(red: 1, green: 0.95, blue: 0.40) }
                return WinampTheme.lcdGlow
            }()
            context.fill(Path(rect), with: .color(color))
            y -= segH
            drawn += segH
        }
        // peak marker
        let peakY = bottom - CGFloat(peaks[i]) * size.height
        let markerRect = CGRect(x: x, y: max(1, peakY - 2), width: barW, height: 2)
        context.fill(Path(markerRect), with: .color(.white.opacity(0.85)))
    }
}

@MainActor
private func drawOscilloscope(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    let samples = engine.oscilloscope
    guard samples.count > 1 else { return }
    let midY = size.height / 2

    // Center reference line
    let refPath = Path(CGRect(x: 0, y: midY - 0.5, width: size.width, height: 1))
    context.fill(refPath, with: .color(WinampTheme.lcdGlow.opacity(0.15)))

    // Build waveform path
    var path = Path()
    for i in 0..<samples.count {
        let x = CGFloat(i) / CGFloat(samples.count - 1) * size.width
        let y = midY + CGFloat(samples[i]) * (size.height * 0.45)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else      { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    // thick glow stroke
    var glowCtx = context
    glowCtx.addFilter(.blur(radius: 4))
    glowCtx.stroke(path, with: .color(WinampTheme.lcdGlow.opacity(0.6)), lineWidth: 4)
    // crisp foreground line
    context.stroke(path, with: .color(WinampTheme.lcdGlow), lineWidth: 1.6)

    // Trigger dot
    let lastY = midY + CGFloat(samples.last ?? 0) * (size.height * 0.45)
    let dot = CGRect(x: size.width - 4, y: lastY - 2, width: 4, height: 4)
    context.fill(Path(ellipseIn: dot), with: .color(.white))
}

@MainActor
private func drawPlasma(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    // A fast plasma — sample at a coarse grid to keep it cheap on the CPU,
    // then fill rectangles. Looks suitably retro on a small panel.
    let cell: CGFloat = 6
    let cols = Int(size.width / cell) + 1
    let rows = Int(size.height / cell) + 1
    let phase = engine.phase

    for r in 0..<rows {
        for c in 0..<cols {
            let x = Double(c) / Double(cols)
            let y = Double(r) / Double(rows)

            // Classic plasma sum-of-sines.
            let v = sin(x * 8 + phase)
                  + sin(y * 6 - phase * 1.3)
                  + sin((x + y) * 5 + phase * 0.7)
                  + sin(sqrt(pow(x - 0.5, 2) + pow(y - 0.5, 2)) * 18 + phase * 1.6)

            let n = (v + 4) / 8 // normalize to 0...1
            let intensity = max(0, min(1, n))
            // map intensity to a phosphor-green ramp with a hint of cyan/yellow
            let color = Color(
                red: intensity > 0.75 ? 0.4 + (intensity - 0.75) * 2.4 : 0.05 + intensity * 0.4,
                green: 0.2 + intensity * 0.8,
                blue: intensity > 0.4 ? 0.1 + intensity * 0.5 : 0.05
            )
            let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
            context.fill(Path(rect), with: .color(color))
        }
    }
}
