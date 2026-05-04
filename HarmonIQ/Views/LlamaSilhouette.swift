import SwiftUI

/// Easter egg: a tiny phosphor-green pixel-art llama in a beveled panel,
/// captioned in lowercase Charcoal Phosphor. A wink to a certain late-90s
/// media player whose splash screen famously asserted that *it* did the
/// whipping. HarmonIQ does the listening.
///
/// **Design contract.** This view is intentionally:
///   * stateless — no @State, no gestures, no logic;
///   * size-bounded — the silhouette renders at `Self.silhouetteSize`
///     (~80×60pt) regardless of caller layout;
///   * theme-pure — every color/font/background flows through
///     `WinampTheme`. No raw RGB, no `.system(...)`, no inline gradients.
///
/// The coder agent owns conditional rendering, gestures, and any About-screen
/// integration — this file is the visual primitive only.
struct LlamaEasterEgg: View {
    /// Pixel-art canvas size in points. 80×60 is the spec, 20 cols × 15 rows
    /// at 4pt per pixel — large enough to read as a llama, small enough to
    /// sit unobtrusively in a footer.
    static let silhouetteSize = CGSize(width: 80, height: 60)

    /// Lowercase per Charcoal Phosphor: LCD readouts read as machine output,
    /// and machines (in 1997) didn't shout. The line tips a hat to the
    /// "really whips the llama's ass" splash without quoting it — HarmonIQ's
    /// quieter sibling.
    static let homage = "it really spins the records right"

    var body: some View {
        VStack(spacing: 6) {
            Canvas { context, size in
                drawLlama(context: context, size: size)
            }
            .frame(width: Self.silhouetteSize.width,
                   height: Self.silhouetteSize.height)
            .accessibilityHidden(true)

            Text(Self.homage)
                .font(WinampTheme.lcdFont(size: 9))
                .foregroundStyle(WinampTheme.lcdGlow)
                .shadow(color: WinampTheme.lcdGlow.opacity(0.4), radius: 1)
                .accessibilityLabel("Easter egg: \(Self.homage)")
        }
        .bevelPanel(corner: WinampTheme.Corner.panel)
    }

    // MARK: - Pixel grid

    /// 20 cols × 15 rows. `1` = lit phosphor pixel, `0` = unlit.
    /// Llama in profile, facing right:
    ///   - rows 0-1   : ears + crown of head
    ///   - rows 2-6   : long neck
    ///   - row 7      : back + tail stub
    ///   - rows 7-10  : body
    ///   - rows 11-14 : four legs (front pair + back pair) with hooves
    private static let grid: [[UInt8]] = [
        // 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19
        [  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0 ], // 0  ear tips
        [  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0 ], // 1  ears + skull top
        [  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0 ], // 2  head + snout start
        [  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0 ], // 3  head + snout
        [  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0 ], // 4  jaw
        [  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0 ], // 5  upper neck
        [  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0 ], // 6  neck
        [  0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0 ], // 7  back + tail stub
        [  0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0 ], // 8  body
        [  0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0 ], // 9  body
        [  0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0 ], // 10 belly
        [  0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0 ], // 11 leg tops
        [  0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0 ], // 12 legs
        [  0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0 ], // 13 legs
        [  0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0 ], // 14 hooves
    ]

    private static let gridCols = 20
    private static let gridRows = 15

    private func drawLlama(context: GraphicsContext, size: CGSize) {
        // Each grid cell is rendered as a flat rectangle — pixel art, no
        // anti-aliasing, no gradient. The faint bloom around the silhouette
        // is the LCD glow shadow on the parent Text path; the canvas itself
        // is sharp like a scanned-out CRT pixel.
        let cellW = size.width / CGFloat(Self.gridCols)
        let cellH = size.height / CGFloat(Self.gridRows)
        // Hairline overlap (0.5pt) prevents seams between adjacent lit
        // pixels at non-integer cell sizes.
        let overlap: CGFloat = 0.5

        for r in 0..<Self.gridRows {
            let row = Self.grid[r]
            for c in 0..<Self.gridCols where row[c] == 1 {
                let rect = CGRect(
                    x: CGFloat(c) * cellW,
                    y: CGFloat(r) * cellH,
                    width: cellW + overlap,
                    height: cellH + overlap
                )
                context.fill(Path(rect), with: .color(WinampTheme.lcdGlow))
            }
        }
    }
}

#Preview {
    ZStack {
        WinampTheme.appBackground.ignoresSafeArea()
        LlamaEasterEgg()
    }
}
