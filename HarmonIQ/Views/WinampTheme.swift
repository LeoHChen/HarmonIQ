import SwiftUI
import UIKit

/// Centralised Winamp-flavored theme: gunmetal panels, lime LCD, beveled chrome.
enum WinampTheme {
    // Panel colors — gradient stops for the classic 3D-extruded plastic look.
    static let panelTop      = Color(red: 0.36, green: 0.40, blue: 0.46)
    static let panelMid      = Color(red: 0.20, green: 0.23, blue: 0.27)
    static let panelBottom   = Color(red: 0.12, green: 0.14, blue: 0.17)

    static let backgroundTop = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let backgroundBot = Color(red: 0.03, green: 0.03, blue: 0.05)

    static let bevelLight = Color(red: 0.65, green: 0.70, blue: 0.78)
    static let bevelDark  = Color(red: 0.04, green: 0.05, blue: 0.07)

    // LCD / readout colors — phosphor green like the original Winamp display.
    static let lcdBackground = Color(red: 0.04, green: 0.06, blue: 0.04)
    static let lcdGlow       = Color(red: 0.40, green: 1.00, blue: 0.55)
    static let lcdDim        = Color(red: 0.25, green: 0.55, blue: 0.30)

    // Accent — phosphor green that matches AccentColor.colorset.
    static let accent        = Color(red: 0.40, green: 1.00, blue: 0.55)

    static let panelGradient = LinearGradient(
        colors: [panelTop, panelMid, panelBottom],
        startPoint: .top, endPoint: .bottom
    )

    static let appBackground = LinearGradient(
        colors: [backgroundTop, backgroundBot],
        startPoint: .top, endPoint: .bottom
    )

    /// Bitmap-feeling monospaced display font for LCD readouts.
    static func lcdFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

// MARK: - View modifiers

struct BevelPanel: ViewModifier {
    var corner: CGFloat = 6
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(WinampTheme.panelGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(WinampTheme.bevelLight.opacity(0.55), lineWidth: 1)
                    .blendMode(.plusLighter)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .inset(by: 1)
                    .strokeBorder(WinampTheme.bevelDark.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
    }
}

struct LCDReadout: ViewModifier {
    var corner: CGFloat = 4
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
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(WinampTheme.bevelDark, lineWidth: 1)
            )
            .overlay(
                // very subtle horizontal scanline pattern
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.04), location: 0.0),
                                .init(color: .clear,                location: 0.5),
                                .init(color: .black.opacity(0.20), location: 1.0),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
    }
}

struct ChromeButton: ViewModifier {
    var pressed: Bool = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(WinampTheme.panelGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(WinampTheme.bevelLight.opacity(0.6), lineWidth: 1)
                    .blendMode(.plusLighter)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .inset(by: 1)
                    .strokeBorder(WinampTheme.bevelDark.opacity(0.9), lineWidth: 1)
            )
            .foregroundStyle(WinampTheme.lcdGlow)
            .shadow(color: WinampTheme.lcdGlow.opacity(0.25), radius: 1, x: 0, y: 0)
            .opacity(pressed ? 0.6 : 1.0)
    }
}

extension View {
    func bevelPanel(corner: CGFloat = 6) -> some View {
        modifier(BevelPanel(corner: corner))
    }
    func lcdReadout(corner: CGFloat = 4) -> some View {
        modifier(LCDReadout(corner: corner))
    }
    func chromeButton(pressed: Bool = false) -> some View {
        modifier(ChromeButton(pressed: pressed))
    }
}

// MARK: - Decorative

/// Faux-EQ vertical bar visualizer that dances when `isAnimating` is true.
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
                                colors: [WinampTheme.lcdGlow, WinampTheme.lcdDim],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: max(2, (geo.size.width - CGFloat(bars - 1) * 2) / CGFloat(bars)),
                               height: max(2, geo.size.height * h))
                        .shadow(color: WinampTheme.lcdGlow.opacity(0.3), radius: 1)
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
