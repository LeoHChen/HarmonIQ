# HarmonIQ v1.2 — Proposal

> **Status:** research synthesis. No code shipped. Open for review.
> **Sources:** [WINAMP_INSPIRATION.md](WINAMP_INSPIRATION.md) · [PERF_COLD_LAUNCH.md](PERF_COLD_LAUNCH.md) · [TAG_WRITING_LIBRARY.md](TAG_WRITING_LIBRARY.md)

## 1. Theme of the release

v1.2 is a **polish + capability** release, not a feature blowout. Three pillars:

1. **Cold-launch speedup** — measurable, conservative, real-device-validated.
2. **Honor the Charcoal Phosphor theme deeper** — close visible drift, lean harder into the Winamp 2.x design language where it earns its keep.
3. **Make the library editable** — first iOS release where a HarmonIQ user can fix bad ID3 tags in-app, with optional AI assist.

Plus the **App Store launch logistics** (issue #118), since v1.2 is the first public release.

## 2. Recommended v1.2 commitment

What I'd actually ship under the v1.2 milestone (12 issues already filed):

| # | Issue | Verdict | Why |
|---|---|---|---|
| 107 | Cold-launch speedup | **In** | Top 3 wins from the perf brief give 40 %+ improvement; 2–3 PRs |
| 108 | Albums / Artists scroll @ 60 fps | **In** | Pairs with 107; same surface area |
| 109 | Indexer parallelization | **Defer to v1.3** | Lower user impact; introduces concurrency risk; do after we re-measure on device |
| 110 | Design consistency sweep | **In** | Trivial scope; #117 found 5+ stragglers already (subPanelHeader gradient, etc.) |
| 111 | Charcoal Phosphor polish round | **In** | Designer-led; bundle with 110 if scope allows |
| 112 | SwiftUI player ("None") parity | **In** | High user-visible impact; #117 brief gives the checklist |
| 113 | Tag-writing library research | **Done** | (this brief) |
| 114 | ID3 edit sheet (Tier 1 + Tier 2 AI) | **In, split** | Tier 1 ships in v1.2; Tier 2 (AI) ships in v1.2 only if 1.2 isn't slipping |
| 115 | Bulk ID3 cleanup | **Defer to v1.3** | Stretch by design; ride on Tier 2 |
| 117 | Winamp inspiration research | **Done** | (this brief) |
| 118 | App Store launch logistics | **In** | Hard prerequisite for public release |
| 106 | Cold-launch profile | **Done** | (this brief) |

**Net v1.2 implementation issues: 7** (107, 108, 110, 111, 112, 114-tier1, 118). Tier 2 AI and Charcoal polish bundle is risk-adjustable.

## 3. The three research findings, distilled

### 3a. Performance — `PERF_COLD_LAUNCH.md`

Top 3 wins, ranked by impact × ease:

1. **Defer `AVAudioSession` activation off `HarmonIQApp.init()`** → −80 to −95 ms on every cold launch. Move into the `body.task` after `loadFromDisk()`. Tiny, low-risk, biggest single win.
2. **Move `LibraryStore.mergeTracks` sort off the main actor** → −50 to −120 ms at 5–10 k tracks. Mirror the `MusicIndexer.runIndex` pattern: sort detached, hop back for the assignment.
3. **Skip `mirrorArtwork*ToLocalCache` walks when nothing changed** → −20 to −80 ms per drive. Add a per-folder mtime+count fingerprint parallel to the existing `lastScanFingerprint`.

**Combined target:** ~640 ms → ~400 ms time-to-populated-paint on a 5 k-track drive. Clears the ≥25 % bar #107 set, with margin.

**Caveat (the coder flagged this):** all numbers are simulator-side. The implementer should re-measure on a real device and a real drive (with security-scoped bookmark resolution included) before locking the fix.

### 3b. Tag library — `TAG_WRITING_LIBRARY.md`

**Pick: `ID3TagEditor` (chicio, MIT)** for v1.2 Tier 1. Rationale:

- Actively maintained — v5.5.0 January 2026, Swift 6 support
- MIT — no LGPL-on-iOS ambiguity (TagLib's biggest problem)
- Pure Swift, SPM-native, ~tens of KB binary impact
- In-place writes that drop into `BookmarkStore.withAccess` cleanly

**Trade-off:** mp3-only. m4a and flac surface a "format not yet editable" state in the v1.2 edit sheet. mp3 is 50–70 % of typical libraries, so the first ship is meaningful.

**v1.3 follow-ups (filed as new issues if user approves):**
- m4a writer (hand-rolled atom updates vs. `SFBAudioEngine` spike)
- flac writer (purpose-built Vorbis comments)
- TagLib reconsideration if/when a maintained Swift wrapper appears

### 3c. Winamp inspiration — `WINAMP_INSPIRATION.md`

10 follow-ups proposed; ranked by my read of impact-per-LOC:

| Rank | Proposal | LOC est. | v1.2 candidate? |
|---|---|---|---|
| 1 | **Spectrum peak-hold caps** — `bandPeaks` is already on `VisualizerEngine`, just unwired | ~10 lines | **Yes** — bundle with #111 |
| 2 | **Hoist `subPanelHeader()` modifier** — duplicated `Color(white: 0.18)→0.10` gradient | ~30 lines | **Yes** — fits #110 trivially |
| 3 | **`ScrollingTitle` SwiftUI primitive** — generalize `ScrollingBitmapText` for any font | ~80 lines | **Yes** — #112 needs it for parity |
| 4 | **Inset LCD strip in SwiftUI player** — `WinampTheme.lcdInset()` | ~20 lines | **Yes** — #112 |
| 5 | **EQ response curve overlay** — `Path` polyline behind the band knobs | ~40 lines | **Yes** — bundle with #111 |
| 6 | **Visualizer auto-rotation mode** — MilkDrop-style cycle every 30s | ~120 lines | **No** — defer to v1.3 |
| 7 | **Render `gen.bmp` in skinned EQ + Playlist title bars** | ~60 lines | **No** — defer to v1.3 |
| 8 | **Windowshade mode** (double-tap LCD to collapse player) | ~150 lines | **No** — defer to v1.3 |
| 9 | **`region.txt` non-rectangular skin masks** — high novelty | ~250 lines | **No** — defer to v1.3 (cool but expensive) |
| 10 | **Quiet llama easter egg in About** | ~20 lines | **Yes** — sneak into the launch logistics PR |

Top 5 fold cleanly into already-filed v1.2 issues — no new issues needed for them. Items 6–9 should be filed as v1.3 candidates if the user approves the proposal.

## 4. Suggested execution order

After v1.1 finishes its TestFlight soak and goes live on the App Store, dispatch coder (and designer for #110/#111) in this order:

1. **#107 Cold-launch speedup** — three small PRs, lands the user-visible perf win first.
2. **#108 Grid scroll @ 60 fps** — pairs naturally with #107's profiling work.
3. **#110 + #111 Design consistency + Charcoal polish** — designer-led; bundle peak-hold caps, subPanelHeader modifier, EQ response curve, inset LCD, llama easter egg into one or two PRs.
4. **#112 SwiftUI player parity** — needs `ScrollingTitle` primitive from step 3.
5. **#114 Tier 1 ID3 edit sheet** — independent from above; can start in parallel.
6. **#114 Tier 2 AI suggestions** — gated on Tier 1; fold under same milestone if v1.2 is on track.
7. **#118 App Store launch logistics** — final stretch; screenshots reflect everything above.

## 5. Open decisions for the user

1. **Approve commit-to-v1.2 list above?** Specifically: deferring **#109 (indexer parallelization)** and **#115 (bulk ID3 cleanup)** to v1.3.
2. **File the 4 new v1.3 candidates** from the Winamp follow-ups (auto-rotation, `gen.bmp` rendering, windowshade, `region.txt` masks)?
3. **Tier 2 AI ID3 cleanup confidence**: ship in v1.2 if on track, slip to v1.3 if not. Acceptable?
4. **Real-device perf re-measurement** before merging #107 PRs — does the user want to do this themselves, or should the release agent capture an Instruments trace as part of the PR review?
5. **Llama easter egg** — yes, no, or "we'll see what designer comes up with"?

## 6. What's NOT in v1.2

Calling this out so it's clear we declined them, not forgot them:

- Plugin / DSP architecture (out of scope per #117 guardrail)
- Modern Winamp 5 skin format (`.wal`) — only classic `.wsz` is parsed today
- m4a and flac tag editing (v1.3)
- Cross-drive playlists (long-standing limitation, not in any milestone)
- Lyrics, social sharing, cloud sync (philosophical no — not in roadmap)
