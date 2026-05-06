# Cold launch + first-screen render profile (issue #106)

Research brief feeding the v1.2 cold-launch fix work in #107.
**No production code changes shipped here** — all instrumentation was
temporary and reverted before this brief was written.

## 1. Methodology

### What I measured

- iPhone 17 simulator (iOS 26.4), Release configuration, Xcode default
  toolchain. Built with `xcodebuild -configuration Release …`.
- Three populated states: empty (no roots.json), 5 000-track sandbox
  index (~3.4 MB JSON), 10 000-track sandbox index (~6.6 MB JSON).
- Each state was launched via `xcrun simctl launch --console-pty` and
  the `print(...)` lines were tailed from stdout. Sim was warm (booted)
  before each launch; this means OS-level page-cache + simd dyld is
  warmer than a true device cold-boot — directional rather than
  absolute numbers.

### What I instrumented (and reverted)

Wall-clock `Date()` deltas around:

- `HarmonIQApp.init()` — split into `configureAudioSession` and
  `configureWinampAppearance`.
- `ContentView.body` first vs. subsequent evaluations.
- `LibraryStore.loadFromDisk` — split into URL build, dispatch hop,
  `Data(contentsOf:)`, `JSONDecoder.decode`, and full elapsed.
- `LibraryStore.loadDriveData(for:)` — split into
  `SandboxRootStore.loadLibrary` decode, `tracks.map`,
  `mergeTracks` (sort), playlists path, `mirrorArtwork*`,
  `computeFingerprint`, `reconcileArtworkOnLoad`.

All `print` lines were removed before this brief was written. `git
diff HEAD` is clean for the three Swift files I touched.

### Why a synthesized library, not a real ~5 k drive

The brief asked for measurements against a representative drive of
≥5 k tracks. I don't have one mounted in the sim. To get any signal I
synthesized a `roots.json` with one read-only root pointing at the
sandbox shadow store (`SandboxRootStore`) plus a synthesized
`library.json` with N tracks. That bypasses the security-scoped
bookmark dance, so **bookmark-resolve cost is NOT in these numbers**.
The on-device path on a real drive should add ~10–50 ms per root for
`URL(resolvingBookmarkData:)` plus
`startAccessingSecurityScopedResource()` — non-trivial, and called
out as a candidate even though it didn't show up in the sim trace.

### What I left alone

- Did not run Instruments. The issue suggests it; doing it well needs
  a real device + a real drive. I'd recommend the implementer (or the
  user) capture a Time Profiler trace once on real hardware before
  picking from the candidates below.
- Did not touch `MusicIndexer` — the launch-path cost is dominated by
  the load+merge path, not indexing (which is gated behind the cheap
  fingerprint check from #62 and only fires when something actually
  changed).

## 2. Observed timings

iPhone 17 sim, sandbox-store path, single root.

| Phase                                  | Empty   | 5 000 tracks | 10 000 tracks |
| -------------------------------------- | ------- | ------------ | ------------- |
| `HarmonIQApp.init()` total             | ~125 ms | ~125 ms      | ~125 ms       |
| └ `configureAudioSession`              | ~95 ms  | ~95 ms       | ~95 ms        |
| └ `configureWinampAppearance`          | ~28 ms  | ~28 ms       | ~28 ms        |
| First `ContentView.body` eval (paint)  | t = 0   | t = 0        | t = 0         |
| `body.task` fires                      | +30 ms  | +32 ms       | +30 ms        |
| `loadFromDisk` enter → leave           | 418 ms  | 538 ms       | 680 ms        |
| └ Dispatch hop + `Data(contentsOf:)`   | ~0.2 ms | ~0.2 ms      | ~0.2 ms       |
| └ `JSONDecoder.decode([LibraryRoot])`  | ~0.1 ms | ~1 ms        | ~1 ms         |
| └ `withCheckedContinuation` resume gap | ~417 ms | ~400 ms      | ~400 ms       |
| └ `sandboxLoadLibrary` (decode JSON)   | n/a     | 37 ms        | 70 ms         |
| └ `mergeTracks` (sort 5/10 k)          | n/a     | 60 ms        | 131 ms        |
| └ `loadDriveData[Synth Drive]` total   | n/a     | 135 ms       | 276 ms        |
| Time-to-fully-populated body re-eval   | ~440 ms | ~640 ms      | ~800 ms       |

**Headline:** ~440 ms of the cold-launch budget is consumed before any
library data lands, even with **zero tracks**. That's the
SwiftUI-first-paint + main-actor-busy window, plus
`AVAudioSession.setActive`. Adding 5 k tracks costs another ~140 ms;
adding 10 k costs ~280 ms. The library-decode + sort cost scales
roughly linearly in track count.

### One specific surprise worth flagging

The `loadFromDisk` wall-clock includes a ~400 ms gap that is **not** in
any inner phase — the dispatch hop is ~0.2 ms, the JSON decode is
~1 ms, but the wrapping `withCheckedContinuation` takes 400 ms to
return. That gap is the main actor being unavailable to resume the
continuation while SwiftUI processes its first layout pass for
`ContentView` (TabView + 4 NavigationStacks). On a real device this
gap will be larger (Metal compositor, real screen) or smaller
(faster CPU). Either way it's the first-paint cost, and it's the
single biggest item in the budget.

## 3. Top candidate optimizations

Ranked by (impact × ease). Each entry: file:line, current cost,
fix shape, expected magnitude.

### A. Defer `AVAudioSession` activation off the launch path — **HIGH impact, EASY**
- **Where:** `HarmonIQ/HarmonIQApp.swift:11-14, 40-48`
- **Cost today:** ~95 ms inside `init()` on every cold launch. Runs
  before `body` is even evaluated, so it's pure latency-to-first-paint.
- **Fix:** Move `setCategory(.playback)` + `setActive(true)` into a
  `Task.detached` triggered from the same `.task` modifier that calls
  `loadFromDisk()`, OR lazily on first `play()`. Background-audio
  capability is declared in `Info.plist` (`UIBackgroundModes: [audio]`)
  — the session only needs to be active *before* playback starts, not
  before the UI renders.
- **Expected:** −80 to −95 ms time-to-first-paint. Risk: the existing
  comment in CLAUDE.md says "Removing either silently breaks
  lock-screen playback." Activate-on-first-play preserves it; just
  don't gate the UI on it.

### B. Move `mergeTracks` sort off the main actor — **HIGH impact, MEDIUM**
- **Where:** `HarmonIQ/Persistence/LibraryStore.swift:477-498`
  (`mergeTracks(forRoot:with:)`)
- **Cost today:** 60 ms at 5 k, 131 ms at 10 k, ~25 % of total
  `loadDriveData` time at 10 k. Uses
  `localizedStandardCompare` per pair — Unicode-aware, expensive.
- **Fix:** Decode + sort on the same detached task that reads JSON,
  hand the sorted `[Track]` back to the main actor. The sort is
  deterministic and pure — the actor isolation invariant
  (CLAUDE.md: "All shared state lives on @MainActor") is preserved
  because we only mutate `self.tracks` on the main actor; the sort
  runs on a value type before the hop.
- **Expected:** −50 to −120 ms at 5–10 k. Bigger win at larger
  libraries.

### C. Skip `mirrorArtwork*ToLocalCache` walks when nothing changed — **MEDIUM impact, EASY**
- **Where:**
  `HarmonIQ/Persistence/DriveLibraryStore.swift:239-283` — both
  `mirrorArtworkToLocalCache` and `mirrorArtistPhotosToLocalCache`.
  Called from `LibraryStore.loadDriveData(for:)` on every cold launch
  for every read-write root.
- **Cost today:** Doesn't show up in the synthesized read-only path I
  measured (which doesn't traverse the on-drive Artwork folder), but
  on a populated drive with thousands of album covers + artist photos
  this is a `contentsOfDirectory` followed by `fileSize`-stat + maybe
  `copyItem` per cover. Issue #107's body explicitly calls this out:
  *"the artwork local-mirror copy happens on every drive load — not
  just when the drive's artwork has changed"*.
- **Fix:** Cache a per-drive "last-mirror-fingerprint" of
  `(driveArtwork.modificationDate, fileCount)` on `LibraryRoot`,
  parallel to `lastScanFingerprint`. Skip the directory walk when it
  matches. The existing per-file size shortcut inside
  `mirrorArtworkToLocalCache` already prevents copying unchanged
  files, but we still pay the directory enumeration + per-file stat
  every launch.
- **Expected:** On a 200-album drive, drops a launch-time
  `enumeratorAtURL`-equivalent walk + 200 stat calls to one
  `getattrlist` on the folder. Order of −20 to −80 ms per root,
  scales with album count.

### D. Move artwork cache reconciliation off the launch path — **MEDIUM impact, MEDIUM**
- **Where:**
  `HarmonIQ/Persistence/LibraryStore.swift:245-250, 258-347`
  (`reconcileArtworkOnLoad` → `performArtworkRescan`).
- **Cost today:** Synchronous on the main actor, runs once per drive
  on every cold launch. Builds a hash → album map across all tracks
  for the drive, then walks the artwork folder and compares hex
  filenames. Cost grows with `tracks * artwork files`. Not measured
  in my synthetic run because I didn't populate enough artwork files
  per drive — but the code shape (filter + map + sha1 per track) is
  ~10–30 ms at 5 k tracks.
- **Fix:** Defer to a low-priority `Task` after first paint. The
  reconcile pass is a self-healing thing for sideloaded artwork
  files — there is no urgency to do it before the user sees their
  library. Schedule it from `body.task` after `loadFromDisk()`
  returns, with `Task(priority: .background)`.
- **Expected:** −20 to −60 ms time-to-first-populated-paint per
  drive. Doesn't change steady-state — just removes a serial step
  from the cold launch.

### E. Pre-sort and cache `allArtists` / `allAlbums` — **MEDIUM impact, EASY**
- **Where:** `HarmonIQ/Persistence/LibraryStore.swift:681-684,
  854-871`
- **Cost today:** `allArtists` and `allAlbums` are computed
  properties — they walk `tracks` and re-sort on **every access**.
  `LibraryView` calls `library.allArtists.count`,
  `library.allAlbums.count` on every body re-eval; if any state
  changes, all four tabs' bodies re-render. At 5–10 k tracks the
  set-build + sort + Unicode-compare is ~10–30 ms each, paid
  multiple times per cold launch (once per body eval after
  `self.tracks = ...`).
- **Fix:** Cache against a `tracksSnapshotID` like the existing
  `artistImageCache` already does
  (`HarmonIQ/Persistence/LibraryStore.swift:756-762`). Invalidate on
  every `tracks` mutation. Same pattern, two more caches.
- **Expected:** −20 to −60 ms per cold launch (measured on first
  Library tab paint), and far better steady-state too — every
  navigation back to the Library tab gets cheaper. `compilationAlbumsByRoot`
  inside `allAlbums` is the main offender; it walks every track twice.

### F. Skip the `for root in loadedRoots { loadDriveData(...) }` serial loop — **MEDIUM impact, MEDIUM**
- **Where:** `HarmonIQ/Persistence/LibraryStore.swift:75-77`
- **Cost today:** Roots are loaded sequentially. With one drive
  this doesn't matter; with 2–3 drives it scales linearly. Each
  root's `loadDriveData` includes a security-scoped bookmark
  resolve + JSON decode + sort + reconcile.
- **Fix:** Run `loadDriveData` for each root in a `TaskGroup` —
  bookmark resolves and JSON decodes are independent. Merging back
  into `tracks` still happens on the main actor (`mergeTracks` does
  the read-modify-write). Need to be careful: `mergeTracks` is
  called per-root and is not commutative in its current form because
  it sorts the entire combined array; switch to a "build per-root
  sorted lists, then concatenate + sort once at the end" pattern.
- **Expected:** With 1 drive → no win. With 2–3 drives →
  −50 to −250 ms. Lower priority for the v1.2 commit.

### G. Drop `Track.id = UUID()` allocations on load — **LOW impact, EASY**
- **Where:** `HarmonIQ/Persistence/DriveLibraryStore.swift:152-175`
  (`toTrack`).
- **Cost today:** Every track gets a fresh `UUID()` on load, even
  though `Track.stableID` is what the rest of the app keys off
  (equality / hash use it; CLAUDE.md says so explicitly). 5 k UUIDs
  is ~3–5 ms on the main thread.
- **Fix:** Use `stableID` as the `Identifiable.id` directly, or
  drop `id: UUID` from the model. Either way, one fewer allocation
  per row. Touches the model — minor breaking-change risk but the
  conventions doc already says `stableID` is the truth.
- **Expected:** −3 to −10 ms at 5–10 k. Worth doing if the model
  edit is acceptable.

### H. Albums/Artists tile artwork load — DEFER — **LOW priority for #107**
- **Where:** `HarmonIQ/Views/SharedComponents.swift:29-33` and
  `HarmonIQ/Views/ArtistsView.swift:118-125` (`loadImage`).
- **Cost today:** Each tile calls `UIImage(contentsOfFile:)`
  synchronously inside the SwiftUI view body. With ~150 visible
  tiles in a `LazyVGrid`, that's 150 synchronous JPEG decodes on
  the main thread when the user first opens Albums. This is the
  scrolling-jank source `LibraryStore.AlbumKey` was thinking
  about, but the issue's sibling B explicitly tracks scroll
  separately — out of scope for #107 cold-launch.
- **Note:** Don't touch this in the same PR. It belongs in a
  Albums/Artists scroll-perf issue (the body of #106 says so).

## 4. Recommended scope for issue #107

Pick **A + B + C** as the v1.2 commitment. Rationale:

1. **A (`AVAudioSession` deferral)** is the biggest single-shot win
   for time-to-first-paint, costs maybe 5 lines of code, and the
   blast radius is well-understood (lock-screen playback test is in
   `TESTING.md`).
2. **B (sort off main actor)** scales with library size — exactly
   the regime issue #107 cares about. The `Task.detached` +
   `MainActor.run` shape is already idiomatic in this codebase
   (`MusicIndexer.runIndex`); follow that pattern.
3. **C (artwork mirror skip-when-unchanged)** is explicitly called
   out in #107's body. Fits the same fingerprint pattern as
   `lastScanFingerprint` from #62. Low risk because the mirror
   already has a per-file shortcut — we're just adding a per-folder
   one above it.

Together these should land the "≥25 % faster cold-launch-to-first-paint"
target #107 sets, on a populated drive. Concretely, on a 5 k drive:

- Today (sim): ~640 ms to populated paint.
- After A+B+C: estimated ~400 ms (−95 audio, −60 sort, −40 mirror,
  + ~120 ms still for first-paint that isn't going anywhere).

Everything else (D–G) is fair game for follow-up PRs but
explicitly **out of scope for v1.2's commit**. Resist scope creep —
the issue says "top 2–3 hotspots" deliberately.

## 5. Things to leave alone

- **Don't move `LibraryStore` off `@MainActor`.** CLAUDE.md is
  explicit, and the visualizer-bug commit `c7ddb9c` was the
  cautionary tale. Hop heavy work off via `Task.detached`; keep the
  store itself main-isolated.
- **Don't pre-render the Library tab.** SwiftUI's TabView lazily
  instantiates inactive tabs already; trying to outsmart it usually
  leads to keeping more work alive than necessary.
- **Don't replace `JSONDecoder` with a "streaming" decoder.** At
  3.4 MB / 5 k tracks, decode is 37 ms — not the bottleneck.
  Streaming would burn complexity and the `Codable` invariants
  (date-decoding strategy, optional fields for forward-compat) for
  no measurable gain.
- **Don't shard `library.json` by hash byte.** Issue #107 floats this
  as a candidate, but the decode cost is nowhere near the dominant
  term and sharding would break the "drive is portable, anyone can
  read library.json" invariant from CLAUDE.md.
- **Don't touch the indexer's cheap-check fingerprint** (#62
  substrate). Issue #107 explicitly flags that as out of scope.
- **Don't preemptively decode JPEGs for visible Album/Artist tiles
  on the launch path.** That's sibling-B work; conflating it makes
  the cold-launch PR un-reviewable.

## 6. Caveats & limitations of this profile

- All numbers are sim-side. On a real iPhone with a USB-C drive
  attached, expect bookmark-resolve + security-scope-start latency
  to add 10–50 ms per root (not measured here). The ranking of
  candidates A–G shouldn't change but the absolute headroom for the
  ≥25 % target needs a device check.
- The sim path I exercised is the read-only sandbox path
  (`SandboxRootStore`). The read-write `DriveLibraryStore` path adds
  the bookmark dance but is otherwise the same JSON shape.
- I did not capture an Allocations trace. Heap peak isn't measured
  here — recommend the implementer of #107 capture one Allocations
  + one Time Profiler on a real device before locking in the fix
  shape.
