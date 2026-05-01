import SwiftUI

/// A bitmap-text marquee. If the text fits inside the viewport, it sits still. If it
/// overflows, it scrolls left continuously, looping with a small gap between repeats.
struct ScrollingBitmapText: View {
    let text: String
    /// Viewport width in skin-space pixels.
    let viewportWidthPx: CGFloat
    var pixelSize: CGFloat = 2

    @State private var startTime = Date()

    var body: some View {
        let viewportW = viewportWidthPx * pixelSize
        let glyphW = SkinFormat.BitmapFont.cellSize.width * pixelSize
        let textW = CGFloat(text.count) * glyphW
        let needsScroll = textW > viewportW
        let gap: CGFloat = 8 * pixelSize

        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let offset: CGFloat = {
                guard needsScroll else { return 0 }
                let elapsed = timeline.date.timeIntervalSince(startTime)
                let speed: CGFloat = 30 * pixelSize  // px per second
                let cycle = textW + gap
                let raw = CGFloat(elapsed) * speed
                return -raw.truncatingRemainder(dividingBy: cycle)
            }()
            HStack(spacing: 0) {
                BitmapText(text: text, pixelSize: pixelSize)
                if needsScroll {
                    Spacer().frame(width: gap)
                    BitmapText(text: text, pixelSize: pixelSize)
                }
            }
            .offset(x: offset)
            .frame(width: viewportW, height: SkinFormat.BitmapFont.cellSize.height * pixelSize, alignment: .leading)
            .clipped()
        }
        .onAppear { startTime = Date() }
        .onChange(of: text) { _ in startTime = Date() }
    }
}
