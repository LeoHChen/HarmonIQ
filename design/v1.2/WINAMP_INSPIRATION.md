# Winamp 2.x / 5 Inspiration Brief — v1.2

> **Summary.** Mining the original Winamp's visual language for HarmonIQ v1.2: where the classic chrome, EQ stickers, playlist editor, visualizers, scrolling LCD title, and easter eggs still have something to teach our SwiftUI player and skinned chrome — without re-implementing plugin architecture or pulling us off our data-sovereignty positioning.

This brief is research for issue [#117](https://github.com/LeoHChen/HarmonIQ/issues/117). It is *not* a spec. Every "Inspiration to apply" item below is a candidate, not a commitment; the "Recommended follow-ups" section at the bottom is what TPM would convert into v1.2/v1.3 issues if the user approves.

The companion theme docs are [`design/PHILOSOPHY.md`](../PHILOSOPHY.md) (icon — *Sun-Bleached Grooves*) and [`design/THEME.md`](../THEME.md) (in-app — *Charcoal Phosphor*). Both are the contract; this brief proposes ways to honor it more deeply.

---

## 1. Classic skin chrome

### What was iconic in Winamp
- A **dark gray rectangle with silver 3D-effect transport buttons** — chunky, square-ish corners, a hot top highlight and a near-black bottom shadow on every raised element. Shelf-stereo skeuomorphism, deliberately industrial.
- **Green LED time digits** in a fixed 9×13 grid, mounted in a recessed inset darker than the panel — the LCD reads as a *physical screen*, not an overlay.
- **Tight clutterbar** of tiny chrome chips on the left edge (O / A / I / D / V) plus mono/stereo lozenges and the kbps/khz mini-LCDs — every readout had a place; nothing floated.
- **Hit targets are pixel-precise.** The 23×18 transport buttons leave essentially zero whitespace between them; the visualizer at 76×16 sits flush against the title text region.
- **Visualizer placement is fixed** — it lives in a 76×16 well immediately under the artist scroll, never moves, and the user accepts that constraint as part of the chrome.
- **No type hierarchy beyond two faces:** the LCD bitmap font for digits/scroll, the small bitmap font for everything else.

### What we have today
- `WinampTheme` (`HarmonIQ/Views/WinampTheme.swift`) already nails Charcoal Phosphor: 1pt bevels, sharp 2–3pt corners, three-stop panel gradient, phosphor LCD lime. `THEME.md` documents tokens and rules.
- Skinned classic player (`HarmonIQ/Views/Skin/SkinnedMainView.swift`) renders pixel-precise sprites at canonical Winamp coordinates and scales to screen width with nearest-neighbor sampling — chunky look survives.
- The "no skin" SwiftUI fallback (`NowPlayingView.swift`) uses `WinampTheme` consistently for the LCD strip and `bevelPanel` for the visualizer container.
- A top-of-window chrome bar (skin cycle / favorite / sleep / close) sits *above* the canonical 275×116 player canvas; it is SF-Symbol-driven and lives in the SwiftUI layer, not the bitmap atlas.

### Inspiration to apply
- **Promote the chrome bar into the canonical canvas, not above it.** The current `chromeButton` row sits in white-on-dark SF Symbols outside the 275×116 sprite world — this is the single biggest break in visual continuity in the skinned view. Either render those buttons as bitmap chips with WinampTheme bevels, or move them into a Winamp-shaped clutterbar column to the left of the LCD.
- **Inset the LCD strip in the SwiftUI player.** In `NowPlayingView`, the LCD readout uses `WinampTheme.lcdFont` correctly but is laid flush with the panel. Add a new `WinampTheme.lcdInset()` modifier that paints `lcdBackground` plus a single inner `bevelDark` line, matching the recessed-screen look the classic skin gets for free.
- **Add a `clutterbar()` primitive** to the theme — a vertical column of 1-letter chrome chips (height 11, width 8, monospaced bold). Then use it for skin-shortcut letters (E for EQ collapse, V for visualizer, S for sleep, etc.) in the SwiftUI player so non-skinned mode gets the same density.
- **Promote `BitmapTime`'s 9×13 grid as the *only* way** to render large LCD digits. NowPlayingView currently renders `formatDuration(...)` with `WinampTheme.lcdFont(size: 12)`. Both work, but a bitmap-rendered time would unify with skinned mode visually.

---

## 2. Equalizer chrome

### What was iconic in Winamp
- **Sticker-y, slightly playful aesthetic.** The EQ window broke the otherwise-industrial rule: gloss labels, drawn-on band frequency tick marks, a curved spline sketched behind the slider knobs hinting the response curve.
- **Preamp visually outranks the bands** — wider knob, set apart by a vertical separator, sometimes a different color cap. It reads as "this one is different and applies first."
- **Auto / Preset chip** is a discrete two-button cluster, each chip with its own beveled edge, in the upper right.
- **A tiny graph of the current curve** sits between PRE and the band sliders in some skins — a real-time spline that updates as you drag. The curve is the strongest signal that EQ is *actually doing something*.
- **The On / Auto / Preset chips show their on/off state by indentation**, not just color. Pressed-in = active.

### What we have today
- `SkinnedEqualizerView.swift` already has 10 bands + preamp, on/off toggle, preset menu. The preamp is correctly visually separated by a vertical 1pt rule (`Rectangle().fill(Color(white: 0.2)).frame(width: 1)`).
- The preset menu chip got a hit-target pass in #83 (10×6 padding, 11pt monospace bold). Per-skin palette colors flow through `SkinPalette`.
- However: the title bar is a hand-rolled `LinearGradient(colors: [Color(white: 0.18), Color(white: 0.10)], ...)`, not a `WinampTheme` modifier. **Theme drift.**
- `VerticalDbSlider` is hand-rolled SwiftUI shapes (track groove, center 0 dB line, knob with shadow) rather than spritesheet-backed — a deliberate trade because building per-skin EQ slider sprites is a lot of work, but the result reads slightly more "iOS slider" than "Winamp slider."

### Inspiration to apply
- **Move the EQ title-bar gradient to a `WinampTheme.subPanelHeader()` modifier.** Both the EQ ("EQUALIZER") and Playlist ("PLAYLIST EDITOR") title bars use the same hand-rolled `Color(white: 0.18) → 0.10` gradient. Hoist it.
- **Render the response curve.** Behind the 10 band knobs (between the rail and the labels), draw a thin lcdGlow polyline interpolating the band values. This is the single change that would make our EQ feel *more Winamp than Winamp's default skin* — most classic skins didn't ship the curve, but the curve is what users wanted. Cheap with `Path` + `Canvas` and zero extra audio work since `eq.bands` already drives it.
- **Tighten the preamp's visual weight.** Today PRE looks identical to a band. Give it a slightly wider knob (24pt vs 22pt), a brighter cap when enabled (`bevelHighlight` instead of `activeColor`), and explicit "PRE" label color even when the EQ is bypassed (the preamp is the band that always matters). Already separated by the rule — finish the job.
- **State-of-the-knob indentation.** The On toggle should look pressed in when active (inset shadow + darker fill) rather than just changing tint. Same for any future "Auto" chip. This is the Winamp 2.x signal language.

---

## 3. Playlist editor

### What was iconic in Winamp
- **Per-row monospace, two-column layout:** index + title left-aligned; duration right-aligned. The title column truncates with ellipsis.
- **Currently-playing row in a different *color*, not background.** Winamp's PLEDIT.TXT distinguishes `Current` foreground from `Normal` foreground; the selection rectangle is a separate concern.
- **Click-to-jump, drag-to-reorder.** The "PL" window was the queue management surface — every interaction lived there.
- **No row chrome.** No leading icon, no chevron, no "more" affordance. Just the text, lit up.
- **Tight vertical rhythm** — rows are ~12pt tall, no padding; the queue is dense by design so 50 tracks fit on screen without scrolling.
- **A footer strip** showed the total queue duration ("48:23 / 1:23:11") in the same bitmap font.

### What we have today
- `SkinnedPlaylistView.swift` is close: monospace 11pt, index + title + duration columns, current-row highlight, scroll-to-current-on-change. `SkinPalette` correctly resolves `current` vs `normal` from PLEDIT.TXT.
- However: same hand-rolled title-bar gradient as EQ (theme drift again), and the current row uses *both* a different foreground (`palette.current`) *and* a `selectedBackground` fill — Winamp typically used color, not fill, for the active row.
- No drag-to-reorder. No total-duration footer. No keyboard shortcuts (the "QUEUE" / "DEL" / "PHYS" menu isn't surfaced).
- Empty state is plain text — sensible but not era-appropriate.

### Inspiration to apply
- **Drop the `selectedBackground` fill on the current row by default.** Use `palette.current` foreground only. Restore the fill if the user is actively *selecting* (multi-select for delete/queue ops — once we ship that). Aligns with how PLEDIT.TXT was designed to be consumed.
- **Add a duration footer.** A `palette.normal` strip at the bottom: `"23 tracks · 1:23:11"` in the same 11pt monospace. Information dense and instantly recognizable.
- **Tighten row vertical padding.** Currently `.padding(.vertical, 3)` — try `1`. Winamp's PL fit ~22 rows on a 232pt window; we should aim for similar density on iPhone Pro.
- **A skin-aware empty state.** Use `BitmapText` to render `"DRAG TRACKS HERE"` when no skin is active just like in skinned mode — the SwiftUI player can borrow the active skin's `text.bmp` if available.

---

## 4. Visualizer fauna

### What was iconic in Winamp
- **The classic 8-bar / 19-bar spectrum** with a green base ramping through amber to red at the top, plus a thin "peak hold" cap that decays. Cheap, instantly recognizable.
- **The plain oscilloscope** — single 76-sample green trace, the ur-visualizer.
- **MilkDrop**'s superpower wasn't polygon count — it was **interpolated transitions between presets** and **beat-reactive parameter modulation** (preset auto-cycles every 16 bars, transitions blend two presets simultaneously over ~2 seconds).
- **AVS**'s superpower was **after-image trails / feedback frames** — every effect ran on top of a slowly fading buffer of the previous frame, so motion painted itself.
- **Geiss** showed that a single pulse-modulated mathematical pattern (think a beat-driven plasma) could feel as alive as a fragment shader.
- **The visualizer cycled on click.** Tap the visualizer, get a new style. Universal mental model.

### What we have today
- 16 visualizer styles in `Visualizers.swift` — spectrum, oscilloscope (8 variants), plasma, mirror, radial pulse, particles, fire, starfield. Coverage is broad.
- Beat detection lives in `VisualizerEngine.advance()` — `beatDetected` is set when peak crosses a rolling-average threshold. Already used by particle spawn and starfield speed boost.
- Spectrum chromatic ramp is centralized via `WinampTheme.spectrumColor(forFraction:)` — a single source of truth for green→amber→red.
- Skinned visualizer (`SkinnedVisualizer.swift`) caches palette colors and falls back to spectrum bars for styles that don't translate to the 24-color VISCOLOR.TXT grid.
- Tap-to-cycle and a center toast confirming the new style name are wired up in both surfaces.

### Inspiration to apply
- **Persistent peak-hold caps on `.spectrum`.** The current spectrum draws bar fills but no separate decaying peak marker. A 1pt `accentRed` line, decaying at ~0.6 units/sec from the highest recent value per band, is the single most "Winamp" detail we don't have. `bandPeaks` is *already in the engine* and unused by the spectrum draw — wire it.
- **Beat-driven parameter modulation pass.** Every visualizer should respond to `engine.beatDetected` with a one-frame parameter spike that decays. Spectrum: bar gain spikes 1.15× and decays back. Plasma: phase rate doubles for 100ms. Particles already do it; generalize the contract.
- **After-image trail option for oscilloscope variants.** AVS's signature look — an exponentially-fading prior-frame buffer underneath the new trace. We can implement as a `Canvas` drawing into a `GraphicsContext` with `BlendMode.plusLighter` over a previous-frame snapshot. Make it a per-style flag.
- **A "Random" rotation mode.** Like MilkDrop's auto-cycle: every 30s on a beat, smoothly fade between two random visualizer styles for ~1.5s. Becomes the default for users who don't want to commit. Persists as `VisualizerSettings.rotationEnabled`.

---

## 5. Now-playing scrolling text

### What was iconic in Winamp
- **The marquee was *always on*** for any title that overflowed the 154px text region, and *always off* if the title fit. No fade, no edge gradient, no easing — just a constant left-drift with a gap and a wrap.
- **Format was `"%n. %a - %t"`** (queue position, artist, title), reused on both the in-window scroll and the lock-screen / OS task list.
- **One scroll speed for everything.** Predictable; no per-track variation.
- **The marquee paused on user interaction** — hovering reset it; clicking the title jumped to the file.

### What we have today
- `ScrollingBitmapText.swift` is excellent — marquee only when the text overflows the viewport, gap of 8 skin-pixels between repeats, 30 px/sec, restarts when text changes. Shipped behavior matches the original almost exactly.
- The SwiftUI `NowPlayingView` does *not* use marquee — it uses `Text(...).lineLimit(1)`, which truncates with `…`. That's the single biggest visual regression vs. skinned mode for long titles.
- `NowPlayingSnapshot` (#104) already fans out structured title/artist info to all the secondary surfaces (mini-player, sleep timer footer, etc.).

### Inspiration to apply
- **Lift `ScrollingBitmapText` behavior into a `ScrollingTitle` SwiftUI primitive** that uses any font (not just `BitmapText`) but matches the same overflow-only marquee semantics. Use it in `NowPlayingView` for the LCD title strip. Use it in mini-player / lock-screen mocks. One marquee implementation, one tuning knob.
- **Standardize the format**: the skinned player uses `"\(t.displayArtist) - \(t.displayTitle)"`. The SwiftUI player splits artist and title across two lines. Pick one; the Winamp homage is the joined single-line scroll.
- **Marquee respects accessibility.** When `accessibilityReduceMotion` is on, freeze the scroll and clip with `…`. The rest of the time, scroll. This is the right call — the Winamp marquee is a quote, not a feature.
- **Marquee in the EQ / Playlist title bars when those grow.** Today they say `"EQUALIZER"` / `"PLAYLIST EDITOR"`. When we eventually add a window subtitle (e.g. `"PLAYLIST EDITOR — Smart Mix '90s Indie"`), the same marquee primitive carries it.

---

## 6. Easter eggs

### What was iconic in Winamp
- **"It really whips the llama's ass."** The DEMO.MP3 line, inspired by Wesley Willis. The single most quoted thing about the app.
- **About box with a cycling "Brought to you by" credit roll**, llama silhouette in the corner, version date.
- **Double-click the title bar to roll up the window** ("windowshade mode" — chrome collapses to just the LCD line).
- **Holding Ctrl while clicking the EQ title bar** flipped the response curve drawing direction.
- **The credits dialog scrolled by itself**, in the same bitmap font, listing every contributor.

### What we have today
- Zero. We have neither a llama nor a credit roll nor a windowshade. The closest analog is the toast that confirms a visualizer cycle.
- Settings has an "About" view (let me note: I haven't audited it for this brief — but it's a place to land an homage).

### Inspiration to apply
- **Windowshade mode for the SwiftUI player.** Double-tap the LCD title strip to collapse `NowPlayingView` to *just* the title scroll + transport row, animating the visualizer / artwork / EQ off. Tap again to restore. Maps perfectly to a SwiftUI `withAnimation` + a `@State var collapsed`.
- **A llama easter egg in the About / Settings credits.** Not the literal Wesley Willis quote (the tone clashes with our restrained brand), but a quiet homage: a tiny black silhouette of a llama at the bottom-right of the About screen, with a tooltip on long-press: *"It still whips."* — affectionate, specific, low-key.
- **Credit roll using `BitmapText`.** A scrollable About screen rendered in the active skin's `text.bmp` font when one is loaded — it would be a delightful shock the first time someone opens About with a custom skin active. Falls back to `lcdFont` when no skin.
- **Subtle skin-cycle confirmation.** Tapping the paint-palette currently cycles silently except for the visual change. A 1-second LCD toast like the visualizer's *(same look, same primitive)* showing the new skin's name would feel right.

---

## 7. Skin engine

### What was iconic in Winamp
- **Classic skins (.wsz):** ZIP of BMPs + a few TXT config files. Files we render today: `main.bmp`, `cbuttons.bmp`, `titlebar.bmp`, `numbers.bmp` / `nums_ex.bmp`, `text.bmp`, `posbar.bmp`, `volume.bmp`, `balance.bmp`, `monoster.bmp`, `playpaus.bmp`, `shufrep.bmp`, `eqmain.bmp`, `eq_ex.bmp`, `pledit.bmp`, plus `viscolor.txt` and `pledit.txt`.
- **Files we *don't* parse**: `region.txt` (custom window region masks — non-rectangular player windows!), `gen.bmp` and `genex.bmp` (general-purpose / mini-browser window chrome), the cursor `.cur` files (`cur_normal`, `cur_titlebar`, `cur_eqslid`, etc. — per-region cursor maps), and the AVS preset files (`*.avs` / `*.milk`).
- **Double-size mode** doubled every coordinate; we already scale fractionally to fill width, which is similar but not identical.
- **"Modern" skins (.wal)**: full XML scripting / freeform window layouts. Out of scope and explicitly excluded by the issue.

### What we have today
- `SkinFormat.swift` documents canonical sprite coordinates exhaustively for the elements we render.
- `WinampSkin.swift` parses 14 atlases + viscolor.txt + pledit.txt.
- `SkinManager.swift` handles bundled + imported skins, swap, and persistence.
- We surface the skin picker via paintpalette button (tap = next, long-press = sheet) on both surfaces.

### Inspiration to apply
- **Render `gen.bmp` chrome around the EQ / Playlist sub-panels.** When a skin loads, the title bars of `SkinnedEqualizerView` and `SkinnedPlaylistView` could use the active skin's `gen.bmp` title art instead of the hand-rolled gradient. This is a *real* underused capability — every classic skin ships `gen.bmp` and we ignore it.
- **Parse `region.txt` and apply it as an iOS `UIBezierPath` mask** on the skinned player canvas. This is the single most expressive classic-skin feature we don't expose. Some classic skins (e.g. "Aqua," "AmpliFire") have non-rectangular silhouettes that simply don't render correctly in any modern Winamp clone — it would be a real moment if we shipped it.
- **A "double-size" toggle.** We scale by `geo.size.width / 275` already; offer a 2× lock that pads the canvas with `WinampTheme.appBackground` on iPad / landscape. Some skins were *designed* for double-size and look better that way.
- **Don't pursue cursor maps.** iOS has no cursor; the iPad pointer is too constrained. Note for the issue and move on.
- **Don't pursue modern skins (.wal / Bento).** Out of scope; conflicts with our static, file-on-drive sovereignty model. Note and move on.

---

## Recommended follow-ups

These are candidate v1.2 / v1.3 issues. One-line summary + one-sentence rationale. TPM converts the approved subset.

1. **Spectrum peak-hold caps** — Wire the unused `bandPeaks` array to draw a 1pt decaying cap above each spectrum bar; it's the single most "Winamp" detail we currently miss.
2. **Inset LCD strip in SwiftUI player** — Add a `WinampTheme.lcdInset()` modifier and apply to `NowPlayingView`'s LCD readout so the SwiftUI player matches the recessed-screen look skinned mode gets for free.
3. **EQ response curve overlay** — Render a thin lcdGlow polyline through the band slider knobs in `SkinnedEqualizerView` so the EQ visibly *shows* what it's doing.
4. **Hoist sub-panel header gradient** — Replace the duplicated hand-rolled `Color(white: 0.18) → 0.10` gradient in EQ + Playlist with a `WinampTheme.subPanelHeader()` modifier; it's documented theme drift.
5. **`ScrollingTitle` SwiftUI primitive** — Generalize `ScrollingBitmapText`'s overflow-only marquee semantics to work with any font, then use it for `NowPlayingView`'s title (currently truncates with `…`).
6. **Render `gen.bmp` in skinned EQ + Playlist title bars** — We parse it, we just don't use it; this is the biggest underused classic-skin capability.
7. **Windowshade mode (double-tap collapse)** — Double-tap the LCD title strip to collapse the SwiftUI player to title + transport only; iconic Winamp interaction with a clean SwiftUI implementation.
8. **Visualizer auto-rotation mode** — Optional MilkDrop-style auto-cycle every 30s on a beat with a 1.5s cross-fade; default-off, persisted in `VisualizerSettings`.
9. **`region.txt` parsing for non-rectangular skinned player** — Apply parsed region as a `UIBezierPath` mask; high-novelty, low-risk, and no current Winamp clone on iOS does this.
10. **Quiet llama easter egg in About** — A tiny silhouette + long-press tooltip in About / Settings credits; affectionate homage that matches our restrained brand.

---

*Written 2026-05-03 for issue #117. References [`design/PHILOSOPHY.md`](../PHILOSOPHY.md) and [`design/THEME.md`](../THEME.md).*
