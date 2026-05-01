import SwiftUI
import UIKit

/// Volume / balance slider where the *track* itself is one of N stacked frames in
/// the atlas — the appropriate frame is picked from the current value to give the
/// classic Winamp "filling" track look. The thumb is the bottom strip of the atlas.
struct SkinnedVolumeSlider: View {
    let atlas: UIImage?
    /// Background frame at index `i` in atlas. (Volume: 28 frames, 68×13. Balance: 28 frames, 38×13.)
    let frameSize: CGSize
    let frameCount: Int
    /// X offset within the atlas where the frame begins (volume=0, balance=9).
    let frameXOffset: CGFloat
    /// Thumb sprite locations.
    let thumbNormal: CGRect
    let thumbPressed: CGRect
    @Binding var value: Double
    var pixelSize: CGFloat = 2

    @State private var isDragging = false

    var body: some View {
        let trackW = frameSize.width * pixelSize
        let trackH = frameSize.height * pixelSize
        let thumbW = thumbNormal.width * pixelSize
        let thumbH = thumbNormal.height * pixelSize
        let travel = max(0, trackW - thumbW)
        let xPos = travel * value

        ZStack(alignment: .leading) {
            Canvas(rendersAsynchronously: false) { ctx, _ in
                guard let cg = atlas?.cgImage else { return }
                let frameIdx = max(0, min(frameCount - 1, Int(value * Double(frameCount - 1) + 0.5)))
                let src = CGRect(x: frameXOffset, y: CGFloat(frameIdx) * frameSize.height,
                                 width: frameSize.width, height: frameSize.height)
                guard let cropped = cg.cropping(to: src) else { return }
                ctx.draw(Image(decorative: cropped, scale: 1, orientation: .up).interpolation(.none),
                         in: CGRect(x: 0, y: 0, width: trackW, height: trackH))
            }
            .frame(width: trackW, height: trackH)

            Canvas(rendersAsynchronously: false) { ctx, _ in
                guard let cg = atlas?.cgImage else { return }
                let rect = isDragging ? thumbPressed : thumbNormal
                guard let cropped = cg.cropping(to: rect) else { return }
                ctx.draw(Image(decorative: cropped, scale: 1, orientation: .up).interpolation(.none),
                         in: CGRect(x: 0, y: 0, width: thumbW, height: thumbH))
            }
            .frame(width: thumbW, height: thumbH)
            .offset(x: xPos, y: (trackH - thumbH) / 2)
        }
        .frame(width: trackW, height: trackH, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !isDragging { isDragging = true }
                    let raw = (drag.location.x - thumbW / 2) / max(1, travel)
                    value = max(0, min(1, raw))
                }
                .onEnded { _ in isDragging = false }
        )
    }
}
