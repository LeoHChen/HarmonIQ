# In-App Theme: "Charcoal Phosphor"

This document describes the visual direction of the in-app interface — panels,
LCD readouts, bevels, transport buttons, and visualizer accents. It is the
counterpart to [`PHILOSOPHY.md`](PHILOSOPHY.md), which governs the icon
artwork. The two are intentionally separate: the icon is sun-bleached and
warm; the player is night-shift and cool, the way a real piece of late-90s
audio gear feels under a desk lamp.

The implementation lives in [`HarmonIQ/Views/WinampTheme.swift`](../HarmonIQ/Views/WinampTheme.swift).
This file is the document; that file is the source. If they ever disagree,
treat the Swift as the truth and update this doc.

## Direction

**Charcoal Phosphor.** A dark graphite chassis — closer to the original
Winamp 2.x default skin than the muted gunmetal we shipped through 1.0 —
holding a deep CRT-green LCD that *actually glows*, with chromatic VU
accents (amber and red) reserved for the spectrum's mid and peak ranges.

The previous palette was slightly blue and slightly soft; this one is
deliberately neutral-warm and deliberately sharp. The bevels are 1px lines,
not 2px gradients. Corners default to 3pt (panels) / 2pt (LCD, buttons),
not 6pt — Winamp 2.x was almost rectilinear, and the eye reads sharp
corners as "this is a control I can press" much faster than soft ones.

## Tokens

All numbers below are defined in `WinampTheme.swift`. Names match.

### Panel chrome

A three-stop vertical gradient that gives a flat panel the illusion of an
extruded plastic edge. The contrast between top and bottom is what makes
the bevel read.

| Token         | RGB                | Role                                         |
| ------------- | ------------------ | -------------------------------------------- |
| `panelTop`    | (0.42, 0.43, 0.45) | Top edge of panels — a hair brighter than mid. |
| `panelMid`    | (0.20, 0.21, 0.22) | Body of panels.                              |
| `panelBottom` | (0.08, 0.09, 0.10) | Bottom edge — near-black for depth.          |

### App background

| Token           | RGB                | Role                                       |
| --------------- | ------------------ | ------------------------------------------ |
| `backgroundTop` | (0.06, 0.06, 0.07) | Top of the app — the "wall behind the player". |
| `backgroundBot` | (0.02, 0.02, 0.03) | Bottom — almost pure black.                |

### Bevels

Three values, not two. The "highlight" / "shadow" pair around panels is
unchanged in concept; the new "buttonHighlight" is a hot inner ridge that
only chrome buttons paint, on the top half only, to mimic the original
2.x transport look.

| Token            | RGB                | Role                                     |
| ---------------- | ------------------ | ---------------------------------------- |
| `bevelLight`     | (0.80, 0.80, 0.82) | Outer highlight ring.                    |
| `bevelHighlight` | (0.95, 0.95, 0.96) | Hot inner ridge on chrome buttons (top half). |
| `bevelDark`      | (0.02, 0.02, 0.03) | Outer shadow ring / LCD inset frame.     |

### LCD (phosphor green CRT)

The screen behind the digits is darker and slightly green-tinted so the
lit text reads as a real glow, not as overlay text on a black panel.

| Token           | RGB                | Role                                 |
| --------------- | ------------------ | ------------------------------------ |
| `lcdBackground` | (0.02, 0.05, 0.03) | Inside-the-LCD black-with-a-hint-of-green. |
| `lcdGlow`       | (0.40, 1.00, 0.50) | Lit phosphor — primary text, accents. |
| `lcdDim`        | (0.20, 0.55, 0.25) | Dim phosphor — secondary text.       |
| `lcdText`       | (0.85, 0.92, 0.85) | Neutral non-glowing on-LCD label text. |

`lcdGlow` is mirrored in `Assets.xcassets/AccentColor.colorset` so SwiftUI's
`.accentColor` matches the in-code token. Keep them in sync.

### Chromatic VU accents

Used by the spectrum, mirror, and radial visualizers as the bar approaches
clipping. Centralised in `WinampTheme.spectrumColor(forFraction:)` so all
visualizers ramp at the same break points (≤0.55: green, 0.55–0.78: amber,
>0.78: red).

| Token         | RGB                | Role                                |
| ------------- | ------------------ | ----------------------------------- |
| `accentAmber` | (1.00, 0.86, 0.30) | Mid-range bars / oscMultiLayer warm trace. |
| `accentRed`   | (1.00, 0.35, 0.30) | Peak bars / clipping warning.       |

### Geometry

| Token                  | Value | Role                                 |
| ---------------------- | ----- | ------------------------------------ |
| `Corner.panel`         | 3pt   | Default radius for `bevelPanel()`.   |
| `Corner.lcd`           | 2pt   | Default radius for `lcdReadout()`.   |
| `Corner.button`        | 2pt   | Default radius for `chromeButton()`. |
| `Corner.small`         | 2pt   | One-off small chrome elements.       |
| `Bevel.line`           | 1pt   | All bevel stroke widths.             |
| `Bevel.highlightAlpha` | 0.60  | Outer top/left highlight ring.       |
| `Bevel.shadowAlpha`    | 0.95  | Outer bottom/right shadow ring.      |
| `Bevel.buttonHighlight`| 0.85  | Inner ridge on chrome buttons.       |

## Rules of consumption

These mirror the system-wide rules in `CLAUDE.md` and the designer-agent
brief — repeated here so any contributor reading the design folder hits
them before reaching for `LinearGradient`.

1. **No hand-rolled backgrounds.** `bevelPanel()`, `lcdReadout()`,
   `chromeButton()`, or `WinampTheme.appBackground`. If a view needs
   something else, *add a new modifier to `WinampTheme.swift`* — do not
   inline a `LinearGradient` in the view file.
2. **No magic numbers.** Spacing, corner radii, bevel widths, font sizes
   live as named tokens in `WinampTheme`. Hoist any inline constants you
   find.
3. **Monospace = `WinampTheme.lcdFont(size:)`.** Do not call
   `.system(.body, design: .monospaced)` directly.
4. **Phosphor accent everywhere selection lives.** Selection,
   focused-control, "playing now" indicator, primary CTA. The amber and
   red accents are reserved for VU range mapping — do not use them as
   primary UI accent without updating this doc.
5. **Spectrum ramp goes through `WinampTheme.spectrumColor(forFraction:)`.**
   Don't rebuild the green→amber→red mapping in a new visualizer.
6. **Dark backgrounds need clear list/scroll backgrounds.** Global
   `UITableView`/`UICollectionView` overrides in `HarmonIQApp` make
   `WinampTheme.appBackground` show through SwiftUI `List`/`ScrollView`.
   Don't undo them locally.
7. **Accessibility.** Targets ≥ 44pt, contrast WCAG AA against `panelMid`,
   support Dynamic Type where text is content (not chrome).

## What changed vs. 1.0 ("muted gunmetal + lime")

For posterity, since the previous theme shipped through 1.0:

* **Panel:** lighter top edge (0.42 vs 0.36) and a darker bottom (0.08
  vs 0.12), with a slightly warmer midtone — graphite, not slate.
* **App background:** flatter and darker — closer to true black so artwork
  pops harder.
* **Bevels:** brighter highlight (0.80 vs 0.65) and blacker shadow (0.02
  vs 0.04). Added `bevelHighlight` for the hot inner ridge on chrome
  buttons; previously chrome buttons only had the same outer highlight as
  panels.
* **LCD:** background slightly greener and slightly darker so the glow
  reads as light. `lcdGlow` blue channel dropped from 0.55 to 0.50 for a
  more pure CRT lime; `AccentColor` updated to match.
* **Corners:** default panel corner went from 6pt to 3pt; LCD/button from
  4pt/5pt to 2pt. Sharper Winamp-2.x square-ish shape.
* **Chromatic accents:** `accentAmber` and `accentRed` are now first-class
  tokens; `spectrumColor(forFraction:)` is the single ramp that the
  spectrum, mirror, radial, and visualizer-thumbnail renderers all use.
* **EQVisualizer:** the mini-player VU bars now ramp red→amber→green→dim
  from top to bottom, like the original 2.x VU.
* **Text:** the "neutral on-LCD" cream-green that was inlined as
  `Color(red: 0.85, green: 0.92, blue: 0.85)` in five views is now
  `WinampTheme.lcdText`.
