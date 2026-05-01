import SwiftUI
import UIKit

/// The Winamp 2.x main player window, rebuilt for iPhone. Lays out canonical sprites
/// at their original pixel coordinates inside a 275×116 skin-space canvas, then scales
/// the whole thing to fill the screen width with crisp nearest-neighbor sampling.
struct SkinnedMainView: View {
    @EnvironmentObject var skinManager: SkinManager
    @EnvironmentObject var player: AudioPlayerManager
    @StateObject private var visEngine = VisualizerEngine()
    @Environment(\.dismiss) private var dismiss

    @State private var scrubbingPosition: Double? = nil
    @State private var showSkinPicker = false
    @State private var showSleepMenu = false

    var body: some View {
        GeometryReader { geo in
            // Fractional scale so the player fills the screen width even when the
            // device width isn't an integer multiple of 275px. Sprites are still
            // rendered with nearest-neighbor sampling (.interpolation(.none)) so
            // the chunky look survives the non-integer scale.
            let pixel = max(1, geo.size.width / SkinFormat.mainWindowSize.width)
            let canvasW = SkinFormat.mainWindowSize.width * pixel
            let canvasH = SkinFormat.mainWindowSize.height * pixel
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    // Tap to cycle to the next skin. The Menu form scrolls poorly
                    // on iPhone once you have a dozen+ skins installed; cycling
                    // is one tap and shows the new name inline.
                    Button {
                        skinManager.cycleToNextSkin()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "paintpalette.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.85), .black.opacity(0.6))
                            Text(skinManager.activeSkin?.displayName ?? "No Skin")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.45), in: Capsule())
                    }
                    .accessibilityLabel("Cycle to next skin")
                    .simultaneousGesture(
                        // Long-press opens a scrollable picker. The contextual
                        // menu we used before couldn't scroll once the skin
                        // list grew past the screen height.
                        LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                            showSkinPicker = true
                        }
                    )

                    Spacer()

                    SleepTimerButton()
                        .environmentObject(player)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85), .black.opacity(0.6))
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 6)
                ZStack(alignment: .topLeading) {
                    background(pixel: pixel, size: CGSize(width: canvasW, height: canvasH))

                    overlays(pixel: pixel)
                        .frame(width: canvasW, height: canvasH, alignment: .topLeading)
                }
                .frame(width: canvasW, height: canvasH)

                SleepTimerCountdown()
                    .environmentObject(player)

                if let err = player.playbackError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.85))
                }

                // Stack the equalizer above the playlist to match Winamp's
                // top-to-bottom window order. The EQ takes a fixed height
                // (sliders + labels need consistent room); the playlist gets
                // the remaining flexible space and scrolls internally when
                // the queue is long.
                SkinnedEqualizerView()
                    .frame(height: 200)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)

                SkinnedPlaylistView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black.ignoresSafeArea())
        }
        .sheet(isPresented: $showSkinPicker) {
            SkinPickerSheet()
                .environmentObject(skinManager)
        }
        .onAppear  { player.setVisualizerActive(true)  }
        .onDisappear { player.setVisualizerActive(false) }
    }

    // MARK: - Background

    @ViewBuilder
    private func background(pixel: CGFloat, size: CGSize) -> some View {
        if let main = skinManager.activeSkin?.main {
            Image(uiImage: main)
                .interpolation(.none)
                .resizable()
                .frame(width: size.width, height: size.height)
        } else {
            Rectangle().fill(Color.black).frame(width: size.width, height: size.height)
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private func overlays(pixel: CGFloat) -> some View {
        let skin = skinManager.activeSkin
        ZStack(alignment: .topLeading) {
            // Time display
            BitmapTime(seconds: player.currentTime, pixelSize: pixel)
                .position(at: SkinFormat.MainElement.timeDisplay.origin, pixel: pixel,
                          width: SkinFormat.MainElement.timeDisplay.width,
                          height: SkinFormat.MainElement.timeDisplay.height)

            // Title text (scrolls if too long for the 154px region)
            ScrollingBitmapText(text: titleString,
                                viewportWidthPx: SkinFormat.MainElement.titleText.width,
                                pixelSize: pixel)
                .position(at: SkinFormat.MainElement.titleText.origin, pixel: pixel,
                          width: SkinFormat.MainElement.titleText.width,
                          height: SkinFormat.MainElement.titleText.height)

            // Visualizer
            SkinnedVisualizer(engine: visEngine, pixelSize: pixel)
                .position(at: SkinFormat.MainElement.visualizer.origin, pixel: pixel,
                          width: SkinFormat.MainElement.visualizer.width,
                          height: SkinFormat.MainElement.visualizer.height)

            // Play state (stop/play/pause)
            playStateView(pixel: pixel, atlas: skin?.playPause)
                .position(at: SkinFormat.MainElement.playState.origin, pixel: pixel,
                          width: SkinFormat.MainElement.playState.width,
                          height: SkinFormat.MainElement.playState.height)

            // Mono / stereo indicator
            monoStereoView(pixel: pixel, atlas: skin?.monoStereo)
                .position(at: SkinFormat.MainElement.monoStereo.origin, pixel: pixel,
                          width: SkinFormat.MainElement.monoStereo.width,
                          height: SkinFormat.MainElement.monoStereo.height)

            // Position slider
            positionSlider(pixel: pixel, atlas: skin?.posBar)
                .position(at: SkinFormat.MainElement.positionSlider.origin, pixel: pixel,
                          width: SkinFormat.MainElement.positionSlider.width,
                          height: SkinFormat.MainElement.positionSlider.height)

            // Volume slider
            SkinnedVolumeSlider(
                atlas: skin?.volume,
                frameSize: SkinFormat.Volume.frameSize,
                frameCount: SkinFormat.Volume.frameCount,
                frameXOffset: 0,
                thumbNormal: SkinFormat.Volume.thumb,
                thumbPressed: SkinFormat.Volume.thumbPressed,
                value: Binding(
                    get: { Double(player.volume) },
                    set: { player.volume = Float($0) }
                ),
                pixelSize: pixel
            )
            .position(at: SkinFormat.MainElement.volumeSlider.origin, pixel: pixel,
                      width: SkinFormat.MainElement.volumeSlider.width,
                      height: SkinFormat.MainElement.volumeSlider.height)

            // Balance slider
            SkinnedVolumeSlider(
                atlas: skin?.balance,
                frameSize: SkinFormat.Balance.frameSize,
                frameCount: SkinFormat.Balance.frameCount,
                frameXOffset: 9,
                thumbNormal: SkinFormat.Balance.thumb,
                thumbPressed: SkinFormat.Balance.thumbPressed,
                value: Binding(
                    get: { Double((player.balance + 1) / 2) },
                    set: { player.balance = Float($0 * 2 - 1) }
                ),
                pixelSize: pixel
            )
            .position(at: SkinFormat.MainElement.balanceSlider.origin, pixel: pixel,
                      width: SkinFormat.MainElement.balanceSlider.width,
                      height: SkinFormat.MainElement.balanceSlider.height)

            // Transport buttons
            transportButtons(pixel: pixel, atlas: skin?.cButtons)

            // Shuffle / Repeat
            shuffleRepeat(pixel: pixel, atlas: skin?.shufRep)
        }
    }

    // MARK: - State views

    @ViewBuilder
    private func playStateView(pixel: CGFloat, atlas: UIImage?) -> some View {
        let state: SkinFormat.PlayState = player.currentTrack == nil
            ? .stop
            : (player.isPlaying ? .play : .pause)
        Canvas(rendersAsynchronously: false) { ctx, _ in
            guard let cg = atlas?.cgImage, let cropped = cg.cropping(to: state.rect) else { return }
            ctx.draw(Image(decorative: cropped, scale: 1, orientation: .up).interpolation(.none),
                     in: CGRect(x: 0, y: 0, width: 9 * pixel, height: 9 * pixel))
        }
        .frame(width: 9 * pixel, height: 9 * pixel)
    }

    @ViewBuilder
    private func monoStereoView(pixel: CGFloat, atlas: UIImage?) -> some View {
        Canvas(rendersAsynchronously: false) { ctx, _ in
            guard let cg = atlas?.cgImage else { return }
            // Stereo lit + mono unlit by default.
            if let stereo = cg.cropping(to: SkinFormat.MonoStereo.stereoLit) {
                ctx.draw(Image(decorative: stereo, scale: 1, orientation: .up).interpolation(.none),
                         in: CGRect(x: 27 * pixel, y: 0, width: 29 * pixel, height: 12 * pixel))
            }
            if let mono = cg.cropping(to: SkinFormat.MonoStereo.monoUnlit) {
                ctx.draw(Image(decorative: mono, scale: 1, orientation: .up).interpolation(.none),
                         in: CGRect(x: 0, y: 0, width: 27 * pixel, height: 12 * pixel))
            }
        }
        .frame(width: 56 * pixel, height: 12 * pixel)
    }

    // MARK: - Sliders

    @ViewBuilder
    private func positionSlider(pixel: CGFloat, atlas: UIImage?) -> some View {
        let pos = scrubbingPosition ?? (player.duration > 0 ? player.currentTime / player.duration : 0)
        BitmapSlider(
            trackAtlas: atlas,
            trackRect: SkinFormat.PosBar.track,
            thumbAtlas: atlas,
            thumbNormal: SkinFormat.PosBar.thumb,
            thumbPressed: SkinFormat.PosBar.thumbPressed,
            value: Binding(
                get: { pos },
                set: { scrubbingPosition = $0 }
            ),
            pixelSize: pixel,
            onEditingChanged: { editing in
                if !editing, let p = scrubbingPosition {
                    player.seek(to: p * player.duration)
                    scrubbingPosition = nil
                }
            }
        )
    }

    // MARK: - Buttons

    @ViewBuilder
    private func transportButtons(pixel: CGFloat, atlas: UIImage?) -> some View {
        HStack(spacing: 0) {
            // Previous
            SpriteButton(atlas: atlas,
                         normal: SkinFormat.CButton.previous.rect,
                         pressed: SkinFormat.CButton.previous.pressedRect,
                         pixelSize: pixel) { player.previous() }
            // Play
            SpriteButton(atlas: atlas,
                         normal: SkinFormat.CButton.play.rect,
                         pressed: SkinFormat.CButton.play.pressedRect,
                         pixelSize: pixel) { player.resume() }
            // Pause
            SpriteButton(atlas: atlas,
                         normal: SkinFormat.CButton.pause.rect,
                         pressed: SkinFormat.CButton.pause.pressedRect,
                         pixelSize: pixel) { player.pause() }
            // Stop
            SpriteButton(atlas: atlas,
                         normal: SkinFormat.CButton.stop.rect,
                         pressed: SkinFormat.CButton.stop.pressedRect,
                         pixelSize: pixel) { player.pause(); player.seek(to: 0) }
            // Next
            SpriteButton(atlas: atlas,
                         normal: SkinFormat.CButton.next.rect,
                         pressed: SkinFormat.CButton.next.pressedRect,
                         pixelSize: pixel) { player.next() }
        }
        .position(at: SkinFormat.MainElement.cButtonsBar.origin, pixel: pixel,
                  width: SkinFormat.MainElement.cButtonsBar.width,
                  height: SkinFormat.MainElement.cButtonsBar.height)
    }

    @ViewBuilder
    private func shuffleRepeat(pixel: CGFloat, atlas: UIImage?) -> some View {
        // Shuffle button
        SpriteButton(
            atlas: atlas,
            normal: player.isShuffleEnabled ? SkinFormat.ShufRep.shuffleOn : SkinFormat.ShufRep.shuffleOff,
            pressed: player.isShuffleEnabled ? SkinFormat.ShufRep.shuffleOnDown : SkinFormat.ShufRep.shuffleOffDown,
            pixelSize: pixel
        ) {
            player.toggleShuffle()
        }
        .position(at: SkinFormat.MainElement.shuffleButton.origin, pixel: pixel,
                  width: SkinFormat.MainElement.shuffleButton.width,
                  height: SkinFormat.MainElement.shuffleButton.height)

        // Repeat button — three states: off / all / one. The classic shufrep.bmp
        // only ships off/on sprites, so we overlay a small "1" badge on top of
        // the on-state when in single-track loop. This is the only way to make
        // .all visually distinct from .one without a custom sprite per skin.
        ZStack(alignment: .topTrailing) {
            SpriteButton(
                atlas: atlas,
                normal: player.repeatMode == .off ? SkinFormat.ShufRep.repeatOff : SkinFormat.ShufRep.repeatOn,
                pressed: player.repeatMode == .off ? SkinFormat.ShufRep.repeatOffDown : SkinFormat.ShufRep.repeatOnDown,
                pixelSize: pixel
            ) {
                player.cycleRepeatMode()
            }
            if player.repeatMode == .one {
                Text("1")
                    .font(.system(size: max(8, 5 * pixel), weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, max(2, 1 * pixel))
                    .background(Color.black.opacity(0.8), in: Capsule())
                    .allowsHitTesting(false)
                    .padding(max(1, 1 * pixel))
            }
        }
        .position(at: SkinFormat.MainElement.repeatButton.origin, pixel: pixel,
                  width: SkinFormat.MainElement.repeatButton.width,
                  height: SkinFormat.MainElement.repeatButton.height)
    }

    // MARK: - Title

    private var titleString: String {
        if let t = player.currentTrack {
            return "\(t.displayArtist) - \(t.displayTitle)"
        } else {
            return "HarmonIQ"
        }
    }
}

// MARK: - Layout helper

private extension View {
    /// Place the receiver at a skin-space origin (`origin` in skin pixels) scaled by `pixel`.
    /// Width/height are skin-space sizes used to size the view.
    func position(at origin: CGPoint, pixel: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        self
            .frame(width: width * pixel, height: height * pixel, alignment: .topLeading)
            .offset(x: origin.x * pixel, y: origin.y * pixel)
    }
}

/// Scrollable skin picker. Used as a sheet from the in-player skin button —
/// the contextual menu form ran out of room once we shipped a dozen+ skins.
struct SkinPickerSheet: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        skinManager.clearSkin()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.black)
                                Image(systemName: "circle.slash")
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .frame(width: 64, height: 28)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.15)))
                            Text("None (SwiftUI player)")
                            Spacer()
                            if skinManager.activeSkin == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Section("Skins") {
                    ForEach(skinManager.skins) { skin in
                        Button {
                            skinManager.selectSkin(skin)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                if let main = skin.main {
                                    Image(uiImage: main)
                                        .interpolation(.none)
                                        .resizable()
                                        .frame(width: 64, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.15)))
                                } else {
                                    Rectangle().fill(Color.gray)
                                        .frame(width: 64, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                Text(skin.displayName)
                                Spacer()
                                if skinManager.activeSkin?.id == skin.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Switch Skin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
