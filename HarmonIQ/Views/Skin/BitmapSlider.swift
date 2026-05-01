import SwiftUI
import UIKit

/// A horizontal Winamp-style slider: a track sprite running the full width plus a
/// draggable thumb sprite. The thumb position is bound to a 0…1 value.
struct BitmapSlider: View {
    let trackAtlas: UIImage?
    let trackRect: CGRect
    let thumbAtlas: UIImage?
    let thumbNormal: CGRect
    let thumbPressed: CGRect
    @Binding var value: Double
    var pixelSize: CGFloat = 2
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var isDragging = false

    var body: some View {
        let trackW = trackRect.width * pixelSize
        let trackH = trackRect.height * pixelSize
        let thumbW = thumbNormal.width * pixelSize
        let thumbH = thumbNormal.height * pixelSize
        let travel = max(0, trackW - thumbW)
        let xPos = travel * value

        ZStack(alignment: .leading) {
            // Track
            Canvas(rendersAsynchronously: false) { ctx, _ in
                guard let cg = trackAtlas?.cgImage, let cropped = cg.cropping(to: trackRect) else { return }
                ctx.draw(Image(decorative: cropped, scale: 1, orientation: .up).interpolation(.none),
                         in: CGRect(x: 0, y: 0, width: trackW, height: trackH))
            }
            .frame(width: trackW, height: trackH)

            // Thumb
            Canvas(rendersAsynchronously: false) { ctx, _ in
                let atlas = thumbAtlas ?? trackAtlas
                let rect = isDragging ? thumbPressed : thumbNormal
                guard let cg = atlas?.cgImage, let cropped = cg.cropping(to: rect) else { return }
                ctx.draw(Image(decorative: cropped, scale: 1, orientation: .up).interpolation(.none),
                         in: CGRect(x: 0, y: 0, width: thumbW, height: thumbH))
            }
            .frame(width: thumbW, height: thumbH)
            .offset(x: xPos)
        }
        .frame(width: trackW, height: max(trackH, thumbH), alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !isDragging {
                        isDragging = true
                        onEditingChanged?(true)
                    }
                    let raw = (drag.location.x - thumbW / 2) / max(1, travel)
                    value = max(0, min(1, raw))
                }
                .onEnded { _ in
                    isDragging = false
                    onEditingChanged?(false)
                }
        )
    }
}
