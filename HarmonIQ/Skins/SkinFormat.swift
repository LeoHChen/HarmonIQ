import CoreGraphics

/// Canonical sprite coordinates for the Winamp 2.x classic skin format.
/// All values are in skin-space pixels (1× scale). Sprite atlas dimensions and per-element
/// rectangles below come from the Winamp Skin SDK specification — every classic skin
/// conforms to the same layout.
///
/// Reference: https://wiki.winamp.com/wiki/Winamp_Skin_File_Format
enum SkinFormat {

    // MARK: - Main window (main.bmp / 275×116)

    static let mainWindowSize = CGSize(width: 275, height: 116)

    /// Position of canonical elements within main.bmp.
    enum MainElement {
        /// Three 9×13 LCD digits + minus + colon at the top-left of the panel.
        /// (We use NUMBERS.BMP for the actual digits — this is just the reserved screen area.)
        static let timeDisplay = CGRect(x: 39, y: 26, width: 99, height: 13)
        /// Scrolling track title text region (uses TEXT.BMP glyphs).
        static let titleText = CGRect(x: 109, y: 23, width: 154, height: 6)
        /// kbps + khz readouts (also TEXT.BMP).
        static let kbps = CGRect(x: 111, y: 43, width: 15, height: 6)
        static let khz = CGRect(x: 156, y: 43, width: 10, height: 6)
        /// Mono / stereo indicators read from MONOSTER.BMP.
        static let monoStereo = CGRect(x: 212, y: 41, width: 56, height: 12)
        /// Spectrum analyzer / oscilloscope area.
        static let visualizer = CGRect(x: 24, y: 43, width: 76, height: 16)
        /// Position slider track region.
        static let positionSlider = CGRect(x: 16, y: 72, width: 248, height: 10)
        /// Volume slider track region.
        static let volumeSlider = CGRect(x: 107, y: 57, width: 68, height: 13)
        /// Balance slider track region.
        static let balanceSlider = CGRect(x: 177, y: 57, width: 38, height: 13)
        /// Five transport buttons (each 23×18, eject 22×16).
        static let cButtonsBar = CGRect(x: 16, y: 88, width: 144, height: 18)
        /// Shuffle (23 wide) and Repeat (47 wide) at the right.
        static let repeatButton = CGRect(x: 210, y: 89, width: 28, height: 15)
        static let shuffleButton = CGRect(x: 164, y: 89, width: 47, height: 15)
        /// Play indicator (3-state) just above the time display.
        static let playState = CGRect(x: 24, y: 28, width: 9, height: 9)
    }

    // MARK: - cbuttons.bmp / 136×36

    /// Classic transport buttons, normal row at y=0 and pressed row at y=18.
    /// Five buttons of 23×18 plus an eject button of 22×16.
    enum CButton: Int, CaseIterable {
        case previous = 0, play, pause, stop, next, eject
        var rect: CGRect {
            switch self {
            case .previous: return CGRect(x: 0,   y: 0, width: 23, height: 18)
            case .play:     return CGRect(x: 23,  y: 0, width: 23, height: 18)
            case .pause:    return CGRect(x: 46,  y: 0, width: 23, height: 18)
            case .stop:     return CGRect(x: 69,  y: 0, width: 23, height: 18)
            case .next:     return CGRect(x: 92,  y: 0, width: 22, height: 18)
            case .eject:    return CGRect(x: 114, y: 0, width: 22, height: 16)
            }
        }
        /// Pressed-state offset within the same atlas. Eject's pressed sits at y=16 (height shrinks).
        var pressedRect: CGRect {
            var r = rect
            r.origin.y = (self == .eject) ? 16 : 18
            return r
        }
    }

    // MARK: - numbers.bmp / 99×13 (or nums_ex.bmp / 108×13)

    /// LCD digits: ten 9-wide cells side by side. nums_ex.bmp adds a wider eleventh cell
    /// for the minus sign (used for negative remaining-time display).
    enum LCDDigit {
        static let cellSize = CGSize(width: 9, height: 13)
        static func rect(for digit: Int) -> CGRect {
            CGRect(x: CGFloat(digit) * 9, y: 0, width: 9, height: 13)
        }
        /// Minus sign location in nums_ex.bmp (only — the classic numbers.bmp doesn't have it).
        static let minusRect = CGRect(x: 99, y: 0, width: 9, height: 13)
    }

    // MARK: - text.bmp / 155×54

    /// Bitmap font: 6 rows × 31 columns of 5×6 glyphs.
    /// Layout follows Winamp's canonical character grid:
    enum BitmapFont {
        static let cellSize = CGSize(width: 5, height: 6)
        static let columns = 31
        // Per-character glyph rect lookup lives in BitmapText, where the charset string
        // is more conveniently authored.
    }

    // MARK: - playpaus.bmp / 42×9

    /// Status indicator: stop=0, play=1, pause=2 (each 9×9 wide; an extra "no track" cell
    /// lives at offset 36, but most skins ignore it).
    enum PlayState: Int {
        case stop = 0, play, pause, working
        var rect: CGRect { CGRect(x: CGFloat(rawValue) * 9, y: 0, width: 9, height: 9) }
    }

    // MARK: - monoster.bmp / 58×24

    /// Mono / stereo: each indicator has lit/unlit states stacked vertically.
    enum MonoStereo {
        /// 29×12 — lit at y=0, unlit at y=12.
        static let stereoLit = CGRect(x: 0,  y: 0,  width: 29, height: 12)
        static let stereoUnlit = CGRect(x: 0,  y: 12, width: 29, height: 12)
        static let monoLit = CGRect(x: 29, y: 0,  width: 27, height: 12)
        static let monoUnlit = CGRect(x: 29, y: 12, width: 27, height: 12)
    }

    // MARK: - shufrep.bmp / 92×60

    /// Shuffle (47×15) and Repeat (28×15), each with 4 states (off/on × not-pressed/pressed)
    /// stacked vertically. Layout:
    ///   y=0    repeat off (not pressed)
    ///   y=15   repeat off (pressed)
    ///   y=30   repeat on  (not pressed)
    ///   y=45   repeat on  (pressed)
    /// Shuffle is at x=28+ for a similar four-state stack.
    enum ShufRep {
        static let repeatOff = CGRect(x: 0, y: 0, width: 28, height: 15)
        static let repeatOffDown = CGRect(x: 0, y: 15, width: 28, height: 15)
        static let repeatOn = CGRect(x: 0, y: 30, width: 28, height: 15)
        static let repeatOnDown = CGRect(x: 0, y: 45, width: 28, height: 15)

        static let shuffleOff = CGRect(x: 28, y: 0, width: 47, height: 15)
        static let shuffleOffDown = CGRect(x: 28, y: 15, width: 47, height: 15)
        static let shuffleOn = CGRect(x: 28, y: 30, width: 47, height: 15)
        static let shuffleOnDown = CGRect(x: 28, y: 45, width: 47, height: 15)
    }

    // MARK: - posbar.bmp / 248×10

    /// Position slider: 248×10 background; 29×10 thumb at (248, 0) normal and (278, 0) pressed.
    enum PosBar {
        static let track = CGRect(x: 0, y: 0, width: 248, height: 10)
        static let thumb = CGRect(x: 248, y: 0, width: 29, height: 10)
        static let thumbPressed = CGRect(x: 278, y: 0, width: 29, height: 10)
    }

    // MARK: - volume.bmp / 68×421 (28 stacked 68×13 background frames + thumbs at the bottom)

    /// Volume slider: 28 background tracks stacked vertically (each 68×13), the thumb
    /// row is at the bottom (15×11 normal at y=422, pressed at y=435).
    enum Volume {
        static let frameSize = CGSize(width: 68, height: 13)
        static let frameCount = 28
        static func backgroundFrame(_ i: Int) -> CGRect {
            CGRect(x: 0, y: CGFloat(i) * 13, width: 68, height: 13)
        }
        static let thumb = CGRect(x: 15, y: 422, width: 14, height: 11)
        static let thumbPressed = CGRect(x: 0, y: 422, width: 14, height: 11)
    }

    // MARK: - balance.bmp / 38×421 (cropped from volume.bmp; 28 frames × 38 wide)

    enum Balance {
        static let frameSize = CGSize(width: 38, height: 13)
        static let frameCount = 28
        static func backgroundFrame(_ i: Int) -> CGRect {
            CGRect(x: 9, y: CGFloat(i) * 13, width: 38, height: 13)
        }
        static let thumb = CGRect(x: 15, y: 422, width: 14, height: 11)
        static let thumbPressed = CGRect(x: 0, y: 422, width: 14, height: 11)
    }
}
