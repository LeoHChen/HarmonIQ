import SwiftUI
import UIKit

/// A pressable bitmap button that swaps between a "normal" and "pressed" sprite when
/// touched. Renders pixels with no smoothing so the skin stays crisp at any scale.
struct SpriteButton: View {
    let normalAtlas: UIImage?
    let pressedAtlas: UIImage?
    let normalRect: CGRect
    let pressedRect: CGRect
    var pixelSize: CGFloat = 2
    var action: () -> Void

    @State private var isPressing = false

    var body: some View {
        let size = CGSize(width: normalRect.width * pixelSize, height: normalRect.height * pixelSize)
        Canvas(rendersAsynchronously: false) { ctx, _ in
            let atlas = isPressing ? (pressedAtlas ?? normalAtlas) : normalAtlas
            let rect = isPressing ? pressedRect : normalRect
            guard let cg = atlas?.cgImage, let cropped = cg.cropping(to: rect) else { return }
            ctx.draw(Image(decorative: cropped, scale: 1, orientation: .up).interpolation(.none),
                     in: CGRect(origin: .zero, size: size))
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressing { isPressing = true } }
                .onEnded { value in
                    isPressing = false
                    let inside = CGRect(origin: .zero, size: size).contains(value.location)
                    if inside { action() }
                }
        )
    }
}

/// Convenience: same atlas for normal+pressed, with rects from SkinFormat.
extension SpriteButton {
    init(atlas: UIImage?,
         normal: CGRect, pressed: CGRect,
         pixelSize: CGFloat = 2,
         action: @escaping () -> Void) {
        self.init(normalAtlas: atlas, pressedAtlas: atlas,
                  normalRect: normal, pressedRect: pressed,
                  pixelSize: pixelSize, action: action)
    }
}
