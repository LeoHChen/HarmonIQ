import SwiftUI
import UIKit

/// Centralised Winamp-flavored theme — charcoal/graphite chrome, deep phosphor-green
/// LCD, sharp 1px bevels, amber/red chromatic accents for VU peaks.
///
/// Updated for issue #72 ("authentic Winamp 2.x" direction). The previous gunmetal
/// + lime palette was muted and slightly blue; this revision pushes toward the
/// classic 2.x default-skin look:
///   * panels are darker and slightly warmer (graphite, not slate);
///   * bevels are tighter and brighter so the 1px highlight/shadow reads sharply;
///   * the LCD lime is more saturated CRT phosphor (think the "111:11" time digits);
///   * spectrum/peak chromatic accents (amber, red) are first-class tokens so the
///     visualizers stop hand-rolling those colors.
///
/// See `design/THEME.md` for the prose direction and rules of consumption.
enum WinampTheme {
    // MARK: - Panel chrome (3D-extruded plastic look)
    //
    // Three-stop gradient from a bright top edge through a graphite midtone down
    // to a near-black bottom. The contrast between `panelTop` and `panelBottom`
    // is what makes the bevel read as a real plastic edge rather than a flat fill.
    static let panelTop      = Color(red: 0.42, green: 0.43, blue: 0.45)
    static let panelMid      = Color(red: 0.20, green: 0.21, blue: 0.22)
    static let panelBottom   = Color(red: 0.08, green: 0.09, blue: 0.10)

    // App background: nearly black with a hair of warmth so artwork pops.
    static let backgroundTop = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let backgroundBot = Color(red: 0.02, green: 0.02, blue: 0.03)

    // Bevel pair — bright highlight, very dark shadow. Both are now ~1px lines
    // around panels and chrome buttons.
    static let bevelLight     = Color(red: 0.80, green: 0.80, blue: 0.82) // top-left highlight
    static let bevelHighlight = Color(red: 0.95, green: 0.95, blue: 0.96) // hot inner highlight on buttons
    static let bevelDark      = Color(red: 0.02, green: 0.02, blue: 0.03) // bottom-right shadow

    // MARK: - LCD readouts (phosphor green CRT)
    //
    // The "screen behind the digits" (`lcdBackground`) is darker and slightly
    // green-tinted so the lit pixels look like they're actually glowing.
    // `lcdGlow` is the lit color; `lcdDim` is the unlit-but-visible secondary
    // text (e.g. artist line under track title, kbps readout).
    static let lcdBackground = Color(red: 0.02, green: 0.05, blue: 0.03)
    static let lcdGlow       = Color(red: 0.40, green: 1.00, blue: 0.50) // matches AccentColor
    static let lcdDim        = Color(red: 0.20, green: 0.55, blue: 0.25)
    /// Neutral on-LCD text — slightly green-tinted off-white for non-glowing
    /// labels (album titles in lists, secondary track text). Reads as "lit
    /// pixels at half brightness" without competing with `lcdGlow`.
    static let lcdText       = Color(red: 0.85, green: 0.92, blue: 0.85)

    // MARK: - Chromatic VU accents
    //
    // The original Winamp 2.x spectrum analyzer ramped green → yellow → red as
    // bars approached clipping. These are tokens for that ramp so the visualizer
    // and library views stop inlining literal RGB.
    static let accentAmber = Color(red: 1.00, green: 0.86, blue: 0.30) // mid-range bar
    static let accentRed   = Color(red: 1.00, green: 0.35, blue: 0.30) // peak / hot bar

    // Phosphor accent — mirrored in Assets.xcassets/AccentColor.
    static let accent      = lcdGlow

    // MARK: - Composed paint
    static let panelGradient = LinearGradient(
        colors: [panelTop, panelMid, panelBottom],
        startPoint: .top, endPoint: .bottom
    )

    static let appBackground = LinearGradient(
        colors: [backgroundTop, backgroundBot],
        startPoint: .top, endPoint: .bottom
    )

    // MARK: - Tokens
    //
    // Hoisted out of the modifiers so views don't have to remember magic numbers
    // when they want a panel-style overlay. The default corner is 3pt — sharper
    // than the previous 6pt — to land closer to the squared-off 2.x feel.
    enum Corner {
        static let panel: CGFloat   = 3
        static let lcd: CGFloat     = 2
        static let button: CGFloat  = 2
        static let small: CGFloat   = 2
    }

    enum Bevel {
        static let line: CGFloat        = 1
        static let highlightAlpha       = 0.60
        static let shadowAlpha          = 0.95
        static let buttonHighlight      = 0.85 // brighter inner-top highlight on buttons
    }

    /// Bitmap-feeling monospaced display font for LCD readouts.
    static func lcdFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    /// Maps a 0…1 spectrum bar fraction to its phosphor-green / amber / red
    /// color. Centralised so the spectrum, mirror, and radial visualizers all
    /// agree on where the breakpoints live.
    static func spectrumColor(forFraction frac: CGFloat) -> Color {
        if frac > 0.78 { return accentRed }
        if frac > 0.55 { return accentAmber }
        return lcdGlow
    }
}

// MARK: - View modifiers

/// Beveled panel — the main "thing on a panel" container. Sharp 1px highlight
/// on top/left, deeper shadow on bottom/right.
struct BevelPanel: ViewModifier {
    var corner: CGFloat = WinampTheme.Corner.panel
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(WinampTheme.panelGradient)
            )
            // Outer highlight — top/left bright edge.
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        WinampTheme.bevelLight.opacity(WinampTheme.Bevel.highlightAlpha),
                        lineWidth: WinampTheme.Bevel.line
                    )
                    .blendMode(.plusLighter)
            )
            // Inner shadow — bottom/right dark edge for depth.
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .inset(by: WinampTheme.Bevel.line)
                    .strokeBorder(
                        WinampTheme.bevelDark.opacity(WinampTheme.Bevel.shadowAlpha),
                        lineWidth: WinampTheme.Bevel.line
                    )
            )
            .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)
    }
}

/// LCD readout — the phosphor screen container. Darker, sharper bevel than the
/// panel because LCDs in the original Winamp sat *inside* the panel.
struct LCDReadout: ViewModifier {
    var corner: CGFloat = WinampTheme.Corner.lcd
    func body(content: Content) -> some View {
        content
            .foregroundStyle(WinampTheme.lcdGlow)
            .shadow(color: WinampTheme.lcdGlow.opacity(0.55), radius: 2, x: 0, y: 0)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(WinampTheme.lcdBackground)
            )
            // Sharp inset — LCDs were recessed into the front panel.
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(WinampTheme.bevelDark, lineWidth: WinampTheme.Bevel.line)
            )
            // Subtle vertical scan gradient — top hot, bottom slightly darker.
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.05), location: 0.0),
                                .init(color: .clear,                location: 0.5),
                                .init(color: .black.opacity(0.30), location: 1.0),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
    }
}

/// Chrome button — small rectangular plastic button with a hot inner highlight.
struct ChromeButton: ViewModifier {
    var pressed: Bool = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: WinampTheme.Corner.button, style: .continuous)
                    .fill(WinampTheme.panelGradient)
            )
            // Outer highlight (top edge bright).
            .overlay(
                RoundedRectangle(cornerRadius: WinampTheme.Corner.button, style: .continuous)
                    .strokeBorder(
                        WinampTheme.bevelLight.opacity(WinampTheme.Bevel.highlightAlpha),
                        lineWidth: WinampTheme.Bevel.line
                    )
                    .blendMode(.plusLighter)
            )
            // Hot inner highlight — only on the top half, gives the button a
            // crisp ridge like the original 2.x transport buttons.
            .overlay(
                RoundedRectangle(cornerRadius: WinampTheme.Corner.button, style: .continuous)
                    .inset(by: WinampTheme.Bevel.line)
                    .trim(from: 0.0, to: 0.5)
                    .stroke(
                        WinampTheme.bevelHighlight.opacity(WinampTheme.Bevel.buttonHighlight),
                        lineWidth: WinampTheme.Bevel.line
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            // Outer dark border (bottom-right shadow).
            .overlay(
                RoundedRectangle(cornerRadius: WinampTheme.Corner.button, style: .continuous)
                    .inset(by: WinampTheme.Bevel.line)
                    .strokeBorder(
                        WinampTheme.bevelDark.opacity(WinampTheme.Bevel.shadowAlpha),
                        lineWidth: WinampTheme.Bevel.line
                    )
            )
            .foregroundStyle(WinampTheme.lcdGlow)
            .shadow(color: WinampTheme.lcdGlow.opacity(0.30), radius: 1, x: 0, y: 0)
            .opacity(pressed ? 0.55 : 1.0)
    }
}

extension View {
    func bevelPanel(corner: CGFloat = WinampTheme.Corner.panel) -> some View {
        modifier(BevelPanel(corner: corner))
    }
    func lcdReadout(corner: CGFloat = WinampTheme.Corner.lcd) -> some View {
        modifier(LCDReadout(corner: corner))
    }
    func chromeButton(pressed: Bool = false) -> some View {
        modifier(ChromeButton(pressed: pressed))
    }
}

// MARK: - Decorative

/// Faux-EQ vertical bar visualizer that dances when `isAnimating` is true.
/// Used in the mini-player chip; cycles through the green→amber→red ramp at
/// the top so it reads as a proper Winamp VU bar at a glance.
struct EQVisualizer: View {
    let isAnimating: Bool
    var bars: Int = 14
    @State private var heights: [CGFloat] = []

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<bars, id: \.self) { i in
                    let h = heights.indices.contains(i) ? heights[i] : 0.2
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: WinampTheme.accentRed,   location: 0.00),
                                    .init(color: WinampTheme.accentAmber, location: 0.30),
                                    .init(color: WinampTheme.lcdGlow,     location: 0.60),
                                    .init(color: WinampTheme.lcdDim,      location: 1.00),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: max(2, (geo.size.width - CGFloat(bars - 1) * 2) / CGFloat(bars)),
                               height: max(2, geo.size.height * h))
                        .shadow(color: WinampTheme.lcdGlow.opacity(0.25), radius: 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear { roll() }
        .onChange(of: isAnimating) { _ in roll() }
    }

    private func roll() {
        if heights.count != bars {
            heights = (0..<bars).map { _ in CGFloat.random(in: 0.15...0.9) }
        }
        guard isAnimating else {
            withAnimation(.easeOut(duration: 0.4)) {
                heights = (0..<bars).map { _ in 0.18 }
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            heights = (0..<bars).map { _ in CGFloat.random(in: 0.15...0.95) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            roll()
        }
    }
}
