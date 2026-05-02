import SwiftUI

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case spectrum
    case oscilloscope
    case plasma
    case mirror
    case circle
    case particles
    case fire
    case starfield

    var id: String { rawValue }
    var title: String {
        switch self {
        case .spectrum:     return "SPECTRUM"
        case .oscilloscope: return "OSCILLOSCOPE"
        case .plasma:       return "PLASMA"
        case .mirror:       return "MIRROR"
        case .circle:       return "RADIAL PULSE"
        case .particles:    return "PARTICLES"
        case .fire:         return "FIRE"
        case .starfield:    return "STARFIELD"
        }
    }
    var icon: String {
        switch self {
        case .spectrum:     return "chart.bar.fill"
        case .oscilloscope: return "waveform.path"
        case .plasma:       return "flame.fill"
        case .mirror:       return "rectangle.split.1x2.fill"
        case .circle:       return "circle.dotted"
        case .particles:    return "sparkles"
        case .fire:         return "flame.fill"
        case .starfield:    return "sparkle"
        }
    }
}

/// Owns the persisted active visualizer style. Change-driven UI updates use
/// the @Published `style` property; the value also lives in UserDefaults so
/// the choice survives app launches.
@MainActor
final class VisualizerSettings: ObservableObject {
    static let shared = VisualizerSettings()

    private let key = "harmoniq.visualizerStyle"

    @Published var style: VisualizerStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: key) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        self.style = VisualizerStyle(rawValue: raw) ?? .spectrum
    }

    /// Cycle to the next style in declaration order, wrapping at the end.
    func cycle() {
        let all = VisualizerStyle.allCases
        let i = all.firstIndex(of: style) ?? 0
        style = all[(i + 1) % all.count]
    }
}

/// Container that sits in NowPlayingView. Uses a TimelineView so we redraw at ~30Hz
/// regardless of @Published throttling, and reads the latest level from the player.
struct VisualizerView: View {
    @EnvironmentObject var player: AudioPlayerManager
    @StateObject private var settings = VisualizerSettings.shared
    @StateObject private var engine = VisualizerEngine()
    @State private var toastUntil: Date = .distantPast

    var body: some View {
        VStack(spacing: 6) {
            // Header bar — shows current style and a cycle button.
            HStack(spacing: 8) {
                Image(systemName: settings.style.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WinampTheme.lcdGlow)
                Text("VIS · \(settings.style.title)")
                    .font(WinampTheme.lcdFont(size: 10))
                    .foregroundStyle(WinampTheme.lcdGlow)
                Spacer()
                Button {
                    cycleAndToast()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .bold))
                        Text("NEXT")
                            .font(WinampTheme.lcdFont(size: 9))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(WinampTheme.lcdGlow)
                    .background(WinampTheme.lcdGlow.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(WinampTheme.bevelDark))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next visualizer style")
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
                    switch settings.style {
                    case .spectrum:     drawSpectrum(context: context, size: size, engine: engine)
                    case .oscilloscope: drawOscilloscope(context: context, size: size, engine: engine)
                    case .plasma:       drawPlasma(context: context, size: size, engine: engine)
                    case .mirror:       drawMirror(context: context, size: size, engine: engine)
                    case .circle:       drawCircle(context: context, size: size, engine: engine)
                    case .particles:    drawParticles(context: context, size: size, engine: engine)
                    case .fire:         drawFire(context: context, size: size, engine: engine)
                    case .starfield:    drawStarfield(context: context, size: size, engine: engine)
                    }
                    drawCRTBezel(context: context, size: size)
                }
            }
            .background(WinampTheme.lcdBackground)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(WinampTheme.bevelDark))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .center) { styleToast }
            .contentShape(Rectangle())
            // Long-press OR double-tap on the surface cycles the style.
            .onLongPressGesture(minimumDuration: 0.4) { cycleAndToast() }
            .onTapGesture(count: 2) { cycleAndToast() }
        }
        .bevelPanel(corner: 6)
    }

    @ViewBuilder
    private var styleToast: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
            let remaining = toastUntil.timeIntervalSince(timeline.date)
            if remaining > 0 {
                let opacity = min(1.0, remaining / 0.4)
                Text(settings.style.title)
                    .font(WinampTheme.lcdFont(size: 14))
                    .foregroundStyle(WinampTheme.lcdGlow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(WinampTheme.lcdBackground.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(WinampTheme.lcdGlow.opacity(0.6)))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .opacity(opacity)
            }
        }
    }

    private func cycleAndToast() {
        settings.cycle()
        toastUntil = Date().addingTimeInterval(1.0)
    }
}

// MARK: - Engine

@MainActor
final class VisualizerEngine: ObservableObject {
    /// 24 spectrum bands. Synthesized from the player's avg + peak by emphasizing different
    /// regions of the band space at different times — gives a believable spectrum from a single value.
    private(set) var bands: [Float] = Array(repeating: 0, count: 24)
    private(set) var bandPeaks: [Float] = Array(repeating: 0, count: 24)
    /// 64-sample oscilloscope buffer (halved from 128 — more than enough for the rendered width).
    private(set) var oscilloscope: [Float] = Array(repeating: 0, count: 64)
    /// Drives the plasma's animated phase.
    private(set) var phase: Double = 0

    /// Particle field state (used by `.particles`). Pre-allocated so per-frame
    /// work is index updates only — no allocations in advance().
    struct Particle { var x: Float; var y: Float; var vy: Float; var life: Float; var maxLife: Float }
    private(set) var particles: [Particle] = Array(repeating: Particle(x: 0, y: 1, vy: 0, life: 0, maxLife: 1), count: 64)
    private var nextParticle: Int = 0

    /// Starfield state (used by `.starfield`). Each star has (x, y) in [-1, 1]
    /// at z=1, projected through 1/z toward viewer.
    struct Star { var x: Float; var y: Float; var z: Float }
    private(set) var stars: [Star] = (0..<80).map { _ in Star(x: Float.random(in: -1...1), y: Float.random(in: -1...1), z: Float.random(in: 0.05...1.0)) }

    /// Fire heat grid: 20 cols × 14 rows, row 0 = bottom (hottest source).
    static let fireCols = 20
    static let fireRows = 14
    private(set) var fireHeat: [Float] = Array(repeating: 0, count: 20 * 14)

    /// Set on the frame a peak spike crosses the rolling average by `beatThreshold`.
    /// Used by particle spawn and starfield speed boost.
    private(set) var beatDetected: Bool = false
    private var peakAvg: Float = 0
    private let beatThreshold: Float = 0.18

    private var lastDate: Date = .distantPast
    private var frameCount: UInt64 = 0
    private var rng = SystemRandomNumberGenerator()

    // Precomputed t-values for the 24 bands so we don't divide in the hot loop.
    private static let bandT: [Float] = (0..<24).map { Float($0) / Float(23) }

    func advance(date: Date, level: SIMD2<Float>, isPlaying: Bool) {
        let dt = max(0, min(0.1, date.timeIntervalSince(lastDate)))
        lastDate = date
        frameCount &+= 1

        let avg = level.x
        let peak = level.y
        let metered = max(avg, peak * 0.7)
        // When the player is playing, floor the energy so bands / oscilloscope /
        // particles stay alive even if AVAudioPlayer metering momentarily reads
        // ~0 (we've seen this on real hardware right after play, and across
        // track boundaries). Real metered signal overrides the floor.
        let energy = isPlaying ? max(0.08, metered) : metered

        // Beat detection: rolling-average peak with a threshold delta.
        let prevAvg = peakAvg
        peakAvg = peakAvg * 0.92 + peak * 0.08
        beatDetected = isPlaying && (peak - prevAvg) > beatThreshold

        // Always advance starfield + particles + fire so they don't freeze on silence.
        advanceStarfield(dt: Float(dt), energy: energy, isPlaying: isPlaying)
        advanceParticles(dt: Float(dt), energy: energy, isPlaying: isPlaying)
        advanceFire(dt: Float(dt), energy: energy, isPlaying: isPlaying)

        // Early-return on silence: decay existing state cheaply without doing trig.
        if energy < 0.001 {
            for i in 0..<bands.count {
                bands[i] *= 0.88
                bandPeaks[i] = max(0, bandPeaks[i] - Float(dt) * 0.6)
            }
            phase += dt * 0.4
            return
        }

        // One scatter draw per frame instead of one per band (24× fewer RNG calls).
        let scatter = Float.random(in: 0.85...1.15, using: &rng)
        let phaseShift = Float(frameCount) * 0.02

        // --- Spectrum
        for i in 0..<bands.count {
            let t = Self.bandT[i]
            let bell1 = expf(-powf((t - 0.2 + sinf(phaseShift) * 0.05) * 4.5, 2))
            let bell2 = expf(-powf((t - 0.55 + sinf(phaseShift * 1.7) * 0.07) * 4.5, 2))
            let bell3 = expf(-powf((t - 0.85 + cosf(phaseShift * 0.9) * 0.04) * 5.0, 2))
            let bandEnergy = energy * (1.05 - t * 0.3)
            let target = min(1.0, bandEnergy * (bell1 * 1.0 + bell2 * 0.8 + bell3 * 0.6) * scatter)
            let smoothing: Float = isPlaying ? 0.55 : 0.2
            bands[i] = bands[i] * (1 - smoothing) + target * smoothing
            if bands[i] > bandPeaks[i] {
                bandPeaks[i] = bands[i]
            } else {
                bandPeaks[i] = max(0, bandPeaks[i] - Float(dt) * 0.6)
            }
        }

        // --- Oscilloscope (64 samples)
        let ampl = isPlaying ? max(0.05, energy) : 0.0
        let baseFreq: Float = 6.0 + energy * 18.0
        let phaseF = Float(frameCount) * 0.18
        for i in 0..<oscilloscope.count {
            let x = Float(i) / Float(oscilloscope.count - 1) * 2 * .pi
            let wave = sinf(x * baseFreq + phaseF) * 0.65
                     + sinf(x * baseFreq * 0.5 + phaseF * 0.7) * 0.25
                     + Float.random(in: -0.08...0.08, using: &rng)
            oscilloscope[i] = wave * ampl
        }

        // --- Plasma: advance time, faster when loud.
        phase += dt * (0.4 + Double(energy) * 2.6)
    }

    private func advanceStarfield(dt: Float, energy: Float, isPlaying: Bool) {
        // Base drift even on silence so the field never freezes; energy + beat boost speed.
        let speed = (isPlaying ? 0.15 : 0.05) + energy * 0.9 + (beatDetected ? 0.6 : 0.0)
        for i in 0..<stars.count {
            stars[i].z -= speed * dt
            if stars[i].z <= 0.02 {
                stars[i] = Star(x: Float.random(in: -1...1, using: &rng),
                                y: Float.random(in: -1...1, using: &rng),
                                z: 1.0)
            }
        }
    }

    private func advanceParticles(dt: Float, energy: Float, isPlaying: Bool) {
        // Spawn rate scales with energy; beats spawn a burst.
        let spawnP: Float = isPlaying ? min(0.85, energy * 2.5) : 0
        let burst = beatDetected ? 8 : (Float.random(in: 0...1, using: &rng) < spawnP ? 1 : 0)
        for _ in 0..<burst {
            particles[nextParticle] = Particle(
                x: Float.random(in: 0...1, using: &rng),
                y: 1.0,
                vy: 0.25 + Float.random(in: 0...0.5, using: &rng) + energy * 0.4,
                life: 0,
                maxLife: 1.4 + Float.random(in: 0...0.8, using: &rng)
            )
            nextParticle = (nextParticle + 1) % particles.count
        }
        for i in 0..<particles.count {
            guard particles[i].life < particles[i].maxLife else { continue }
            particles[i].y -= particles[i].vy * dt
            particles[i].life += dt
        }
    }

    private func advanceFire(dt: Float, energy: Float, isPlaying: Bool) {
        let cols = Self.fireCols
        let rows = Self.fireRows
        // Seed bottom row with energy + jitter (always alive so the flame doesn't go fully black).
        let baseSeed = (isPlaying ? 0.25 : 0.05) + energy * 0.8
        for c in 0..<cols {
            let jitter = Float.random(in: 0.6...1.2, using: &rng)
            fireHeat[c] = min(1.0, baseSeed * jitter)
        }
        // Propagate upward: each cell = average of (lower-left, lower, lower-right) with decay.
        let decay: Float = 1.0 - 1.6 * dt
        for r in 1..<rows {
            for c in 0..<cols {
                let below = fireHeat[(r - 1) * cols + c]
                let bl = fireHeat[(r - 1) * cols + max(0, c - 1)]
                let br = fireHeat[(r - 1) * cols + min(cols - 1, c + 1)]
                let avg = (below * 1.4 + bl * 0.8 + br * 0.8) / 3.0
                fireHeat[r * cols + c] = max(0, avg * decay)
            }
        }
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
        guard h >= 1 else { continue }          // skip sub-pixel bars
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

@MainActor
private func drawMirror(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    // Spectrum reflected from horizontal centerline, top + bottom halves.
    let bands = engine.bands
    let count = bands.count
    let gap: CGFloat = 2
    let totalGap = gap * CGFloat(count - 1)
    let barW = max(1, (size.width - totalGap) / CGFloat(count))
    let mid = size.height / 2

    // Center reference line for that "stage monitor" look.
    let refPath = Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1))
    context.fill(refPath, with: .color(WinampTheme.lcdGlow.opacity(0.2)))

    for i in 0..<count {
        let h = CGFloat(bands[i]) * (size.height * 0.5)
        guard h >= 1 else { continue }
        let x = CGFloat(i) * (barW + gap)
        // color shifts from lime at center to red at the extremes
        let frac = h / (size.height * 0.5)
        let color: Color = {
            if frac > 0.78 { return Color(red: 1, green: 0.35, blue: 0.35) }
            if frac > 0.55 { return Color(red: 1, green: 0.95, blue: 0.40) }
            return WinampTheme.lcdGlow
        }()
        context.fill(Path(CGRect(x: x, y: mid - h, width: barW, height: h)), with: .color(color))
        context.fill(Path(CGRect(x: x, y: mid, width: barW, height: h)),
                     with: .color(color.opacity(0.7)))
    }
}

@MainActor
private func drawCircle(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    // Bars radiate outward from a center circle, length scaled by band[i].
    let bands = engine.bands
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let innerR = min(size.width, size.height) * 0.18
    let maxOuter = min(size.width, size.height) * 0.46

    // Pulsing inner ring — peak energy modulates radius and brightness.
    let energy = bands.max() ?? 0
    let pulseR = innerR * (1.0 + CGFloat(energy) * 0.35)
    let ring = Path(ellipseIn: CGRect(x: center.x - pulseR, y: center.y - pulseR,
                                       width: pulseR * 2, height: pulseR * 2))
    var glowCtx = context
    glowCtx.addFilter(.blur(radius: 3))
    glowCtx.stroke(ring, with: .color(WinampTheme.lcdGlow.opacity(0.5 + Double(energy) * 0.5)), lineWidth: 2)
    context.stroke(ring, with: .color(WinampTheme.lcdGlow), lineWidth: 1)

    // Bars around the ring.
    let count = bands.count
    for i in 0..<count {
        let theta = Double(i) / Double(count) * 2 * .pi - .pi / 2
        let len = CGFloat(bands[i]) * (maxOuter - innerR)
        guard len >= 1 else { continue }
        let cosT = CGFloat(cos(theta))
        let sinT = CGFloat(sin(theta))
        let p1 = CGPoint(x: center.x + cosT * innerR, y: center.y + sinT * innerR)
        let p2 = CGPoint(x: center.x + cosT * (innerR + len), y: center.y + sinT * (innerR + len))
        var path = Path()
        path.move(to: p1)
        path.addLine(to: p2)
        let frac = len / (maxOuter - innerR)
        let color: Color = {
            if frac > 0.78 { return Color(red: 1, green: 0.35, blue: 0.35) }
            if frac > 0.55 { return Color(red: 1, green: 0.95, blue: 0.40) }
            return WinampTheme.lcdGlow
        }()
        context.stroke(path, with: .color(color), lineWidth: 2)
    }
}

@MainActor
private func drawParticles(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    // Soft phosphor floor, then dots spawned at the bottom drift upward and fade.
    let floor = Path(CGRect(x: 0, y: size.height - 1.5, width: size.width, height: 1.5))
    context.fill(floor, with: .color(WinampTheme.lcdGlow.opacity(0.35)))

    for p in engine.particles {
        guard p.life < p.maxLife, p.life >= 0 else { continue }
        let progress = p.life / p.maxLife
        let alpha = 1.0 - progress
        let r: CGFloat = 1.5 + CGFloat(1.0 - progress) * 1.5
        let cx = CGFloat(p.x) * size.width
        let cy = CGFloat(p.y) * size.height
        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        // brighter near birth, cooler as it fades
        let color = Color(
            red: 0.35 + Double(progress) * 0.4,
            green: 1.0,
            blue: 0.35 + Double(1 - progress) * 0.3
        ).opacity(Double(alpha))
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }
}

@MainActor
private func drawFire(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    // Heat-map columns rising from the bottom. Color ramps black → red → orange → yellow → white.
    let cols = VisualizerEngine.fireCols
    let rows = VisualizerEngine.fireRows
    let cellW = size.width / CGFloat(cols)
    let cellH = size.height / CGFloat(rows)
    for r in 0..<rows {
        let y = size.height - CGFloat(r + 1) * cellH
        for c in 0..<cols {
            let h = engine.fireHeat[r * cols + c]
            guard h > 0.04 else { continue }
            let color = fireColor(forHeat: h)
            let rect = CGRect(x: CGFloat(c) * cellW, y: y, width: cellW + 0.5, height: cellH + 0.5)
            context.fill(Path(rect), with: .color(color))
        }
    }
}

private func fireColor(forHeat h: Float) -> Color {
    // 0 → black, 0.25 → deep red, 0.5 → orange, 0.75 → yellow, 1.0 → white-hot.
    let h = max(0, min(1, h))
    if h < 0.25 {
        let t = Double(h / 0.25)
        return Color(red: t * 0.6, green: 0, blue: 0)
    } else if h < 0.5 {
        let t = Double((h - 0.25) / 0.25)
        return Color(red: 0.6 + t * 0.4, green: t * 0.5, blue: 0)
    } else if h < 0.75 {
        let t = Double((h - 0.5) / 0.25)
        return Color(red: 1.0, green: 0.5 + t * 0.45, blue: t * 0.2)
    } else {
        let t = Double((h - 0.75) / 0.25)
        return Color(red: 1.0, green: 0.95, blue: 0.2 + t * 0.8)
    }
}

@MainActor
private func drawStarfield(context: GraphicsContext, size: CGSize, engine: VisualizerEngine) {
    // Stars projected through 1/z. Closer stars are larger and brighter.
    let cx = size.width / 2
    let cy = size.height / 2
    let scale = min(size.width, size.height) * 0.8
    for s in engine.stars {
        // Project from (x, y, z) ∈ ([-1,1], [-1,1], (0, 1]) to screen space.
        let sx = cx + CGFloat(s.x / s.z) * scale * 0.5
        let sy = cy + CGFloat(s.y / s.z) * scale * 0.5
        guard sx >= -2, sx <= size.width + 2, sy >= -2, sy <= size.height + 2 else { continue }
        let depth = max(0.05, min(1.0, s.z))
        let radius: CGFloat = max(0.5, CGFloat(1.0 - depth) * 2.5)
        let alpha = 1.0 - Double(depth) * 0.85
        let rect = CGRect(x: sx - radius, y: sy - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(WinampTheme.lcdGlow.opacity(alpha)))
    }
}
