# HarmonIQ

**Website:** [www.leochen.net/HarmonIQ](https://www.leochen.net/HarmonIQ/) — landing site lives in [`docs/`](docs/).

> **Music for your own collections, ported to your iPhone.**

HarmonIQ is a SwiftUI music player for iPhone and iPad, built for the people who never threw out their MP3 folders — the CD ripper with three external drives full of FLACs, the Napster-era curator with a meticulous "Best Of 2003" directory, the audio-archivist who treats a hard drive like a library and not a cache.

It plays the music **you already own**, straight off your drive, with a player that looks like it was beamed in from 1999 and a 2026 brain bolted on top.

## Why it exists

**Data sovereignty for music.**

- **You own your files.** Not a streaming service that can pull a license tomorrow. The MP3s, ALAC rips, and FLACs on your drive — the ones you ripped, paid for, downloaded, traded — those are yours, and HarmonIQ treats them that way. The on-drive index lives next to the music in a `HarmonIQ/` folder; move the drive, the library moves with it.
- **You own your playlist algorithm.** Smart Play's rule-based modes are pure functions in [`SmartPlay.swift`](HarmonIQ/Player/SmartPlay.swift) — read them, fork them, replace them. The AI modes (Vibe Match, Storyteller, Sonic Contrast) prefer Apple Intelligence's on-device foundation model when available; *your library never leaves your phone.*
- **You own your taste.** No engagement metrics, no recommendation graph, no listening history shipped off for ad targeting.
- **Works offline. Always.** No network at index time, playback time, or AI curation time (with on-device AI on). Plug a USB-C SSD with a few thousand albums into your iPhone on the plane, in the subway, in the woods. It plays.

The vibe is "bring your old MP3 collection forward" — your CD rips and 2003-era downloads deserve a modern player that respects what they are: yours.

## Screenshots

| Sun-Bleached Grooves launch | Winamp-flavored Library |
|---|---|
| <img src="docs/screenshots/launch.png" width="270" alt="Launch screen: vinyl disc on sunset gradient"> | <img src="docs/screenshots/library.png" width="270" alt="Library tab: Smart Play, browse, add a music drive"> |

| Smart Play curators | Skinned (Winamp) player |
|---|---|
| <img src="docs/screenshots/smartplay.png" width="270" alt="Smart Play screen: Pure Random, Artist Roulette, Genre Journey, Album Walk, Decade Shuffle, Freshly Added"> | <img src="docs/screenshots/skinned-player.png" width="270" alt="Skinned player: Base-2.91 skin with spectrum visualizer, equalizer, and playlist editor"> |

## Features

- **Drive-portable library.** Tracks, playlists, and artwork live in a `HarmonIQ/` folder on the drive itself. Plug the same drive into another iPhone and your library shows up unchanged — no reindex, no account.
- **External-drive friendly.** Pick any folder Files can see (USB-C SSD, SMB share, iCloud Drive, on-device storage). Read-only locations are supported via a sandbox shadow store.
- **Real 10-band EQ.** AVAudioEngine + AVAudioUnitEQ — the sliders move the actual signal. Built-in presets (Flat, Rock, Pop, Jazz, Classical, Bass Boost, Vocal Boost) plus persisted custom curves.
- **Smart Play, 14 rule-based + 3 AI modes.** Pure Random, Artist Roulette, Genre Journey, Album Walk, Decade Shuffle, Freshly Added, Quick Hits, Long Player, Discovery Mix, Mood Arc, Deep Cut, One Per Artist, Genre Tunnel, Era Walk — plus **Vibe Match**, **Storyteller**, and **Sonic Contrast**. AI modes save as regular playlists.
- **On-device AI by default.** AI Smart Play prefers Apple Intelligence's foundation model (iOS 26+, iPhone 15 Pro+) — no API key, no upload, no network. Falls back to Anthropic when an API key is configured.
- **Background playback** with full lock-screen / Control Center / Live Activity / Dynamic Island controls.
- **Winamp skins.** Drop classic `.wsz` files in via the importer; 9 bundled. Skinned main window, equalizer, and playlist all render from the original sprites.
- **16 visualizer styles.** Spectrum, oscilloscope, plasma, mirror, radial pulse, particles, fire, starfield — plus 8 fancy oscilloscope variants (neon glow, harmonic layers, mirror wave, filled wave, radial wave, waterfall, Lissajous, beat flash). Tap the visualizer to cycle.
- **Sleep timer.** Auto-stop after a fixed duration (15/30/45/60 min) or at the end of the current track, with a live LCD countdown.

## Requirements

- iOS 16+
- Xcode 15 / Swift 5.9
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — `project.yml` is the source of truth, the `.pbxproj` is generated.

## Build

```bash
xcodegen generate
xcodebuild -project HarmonIQ.xcodeproj -scheme HarmonIQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

If `xcodebuild` complains about missing tools, prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

There is no test target and no lint config — `xcodebuild` is the only check.

## Architecture sketch

Four `@MainActor` singletons, injected at app launch:

| | |
|---|---|
| `LibraryStore` | Aggregates tracks/playlists across all mounted drives. |
| `AudioPlayerManager` | `AVAudioPlayer` wrapper — queue, shuffle, repeat, audio levels. |
| `MusicIndexer` | Detached file walker that writes the index to the drive's `HarmonIQ/` folder. |
| `NowPlayingManager` | Bridges `MPRemoteCommandCenter` to the player. |

Every drive carries `HarmonIQ/library.json`, `HarmonIQ/playlists.json`, and `HarmonIQ/Artwork/` at its root. The app sandbox holds only `roots.json` (the device's bookmarks) and a local artwork mirror — see `CLAUDE.md` for the full persistence model.

## Layout

```
HarmonIQ/
  HarmonIQApp.swift          # Composition root
  Models/                    # Track, Playlist
  Persistence/               # LibraryStore, DriveLibraryStore, BookmarkStore
  Indexer/                   # Music indexer + metadata extractor
  Player/                    # AudioPlayerManager, NowPlayingManager, SmartPlay
  Skins/                     # .wsz parsing + skin manager
  Views/
    Skin/                    # Skinned (Winamp) UI
    *.swift                  # Native SwiftUI library, search, settings
    WinampTheme.swift        # Shared design system
  Resources/Skins/           # Bundled .wsz files
design/                      # Icon design + render script
project.yml                  # XcodeGen source
```

## Releases

See [GitHub Releases](https://github.com/LeoHChen/HarmonIQ/releases) for the full notes and tag history.

### v1.1 — 2026-05-03

The "make it look right, find it fast, keep it offline" release. Polish across the palette, the browse modes, the maintenance flows, and the lock-screen — without giving up the offline-first stance.

**Charcoal Phosphor.** A more authentically Winamp-2.x palette: graphite chassis, deeper CRT-green LCD, sharper corners, amber + red chromatic accents in the spectrum visualizer. The whole player feels heavier and more "machined" without changing a single feature. (#76)

**Browse by language.** New Library → **Language** hub partitions the library into Chinese / English / Others using a heuristic CJK + Latin classifier. Useful when your collection sprawls across scripts. (#91)

**Artists, with photos.** New Artists browse renders as a visual grid with representative covers, then upgrades to *real* artist headshots when the opt-in network photo fetcher is enabled (MusicBrainz → Wikidata → Wikimedia → TheAudioDB → Wikipedia). Artist tiles are guaranteed to show a headshot or a placeholder — never an album cover masquerading as the artist. (#92, #94, #96)

**Opt-in artwork on tap.** A new opt-in fetcher (off by default) backfills missing album art from MusicBrainz + Cover Art Archive. Albums view also picks up artwork files dropped manually into `<Drive>/HarmonIQ/Artwork/` — silent reconciliation pass on drive-load. (#74, #79)

**Maintenance, consolidated.** All per-drive library actions live behind one **Refresh…** sheet in Settings: Quick refresh / Reindex tracks / Fetch from internet / Advanced → Rebuild. New `tools/library-doctor.swift` (`--report` / `--dedupe` / `--rebuild`) for offline cleanup; compilation albums fold to one "Various Artists" entry. (#90, #100)

**Lock-screen lockstep.** The lock-screen `MPNowPlayingInfo` widget and the HarmonIQ Live Activity now share a single fan-out path — pause/skip/artwork updates land on both, in the same frame. (#104)

**Visualizer + EQ polish.** Radial Pulse renders unambiguously radial at any energy level. Visualizer style picker commits on first tap. EQ preset picker is easier to tap and faster to commit. (#80, #85, #87)

**AI Smart Play, gracefully absent.** On iPhones without Apple Intelligence and without an Anthropic key configured, the AI section now hides cleanly instead of teasing disabled rows. Cloud fallback continues to work on older devices when a key is configured. (#102)

### v1.0 — 2026-05-02

The "your collection deserves a real player" release. Brings the offline-first, drive-portable foundation up to a 1.0 feature set built around **data sovereignty** for collectors with thousands of MP3s and ripped CDs.

**Functional EQ.** AVAudioEngine + AVAudioUnitEQ replaces AVAudioPlayer; the 10-band sliders move the actual signal. Bundled presets (Flat, Rock, Pop, Jazz, Classical, Bass Boost, Vocal Boost) plus persisted custom curves. (#28)

**On-device AI Smart Play.** Three new modes — **Vibe Match** (free-text vibe → curated queue), **Storyteller** (8–12 track narrative arc), **Sonic Contrast** (alternates by style). Default to Apple Intelligence's foundation model on iOS 26 + iPhone 15 Pro+; falls back to an Anthropic API key when configured. Save any AI-curated queue as a normal drive-resident playlist. (#25, #58)

**Smarter rule-based modes.** Genre Tunnel (stay inside the playing track's genre), Era Walk (chronological tour), Mood Arc, Deep Cut, One Per Artist now ship alongside the original suite — 14 rule-based modes + 3 AI modes total.

**Live Activity for background playback.** Lock-screen banner + Dynamic Island compact / expanded / minimal layouts; throttled tick updates respect ActivityKit budgets. (#18)

**Favorites.** Heart toggle on both player skins; saves to a system "Favorites" playlist on the drive (Option A from the issue), so favorites travel between devices. (#33)

**Fancy oscilloscope visualizers.** Eight new osc styles — Neon Glow, Harmonic Layers, Mirror Wave, Filled Wave, Radial Wave, Waterfall, Lissajous, Beat Flash — bringing the SwiftUI visualizer total to 16. The skinned (Winamp) player tap-cycles through all 16 too. (#26, #27, #36)

**Drive UX overhaul.** Incremental reindex (skip work when the drive is unchanged; only re-extract metadata for files whose mtime changed). Auto-detect drive content via foreground refresh + manual **Reload** button per drive. Force-reindex flag so explicit Reindex never silently no-ops. (#55)

**Settings polish.** Real Version / Build / Commit / Tag / Built-at in the About row (build-time `Info.plist` injection). New **Feedback** section with one-tap links to file feature requests, file bugs, browse open issues, star the repo, and copy build info for triage. AI section captures the user's optional Anthropic key. (#52, #59)

**Public landing site.** [www.leochen.net/HarmonIQ](https://www.leochen.net/HarmonIQ/) — sun-bleached gradient hero, all 9 bundled skins as native previews, 16-style visualizer grid, "Make it yours" contribution invitations. Plain HTML/CSS, no analytics, no tracking. (#57)

**Diagnostics.** `os.Logger` instrumentation in the playback path (subsystem `net.leochen.harmoniq`, category `playback`) — track-finish success flags, decode errors, audio-session interruptions, route changes, security-scope releases. Filter in Console.app to triage mid-track aborts.

**UI consistency.** Skinned-player chrome bar redesigned — five buttons (skin / save-AI / favorite / sleep / close), all 36×36, all hierarchical-white SF Symbols. Search and Playlists tabs gain proper inline titles. Save-AI uses `bookmark.fill` instead of the share-arrow.

### v0.4 — 2026-05-02
- **Sleep timer**: stop after 15/30/45/60 min or at the end of the current track; live LCD countdown sits in the player transport.
- **Visualizer overhaul**: 8 selectable styles (spectrum, oscilloscope, plasma, mirror, radial pulse, particles, fire, starfield); active style persists across launches; long-press or double-tap the visualizer to cycle. The skinned (Winamp) player honors the same choice within its 76×16 + palette constraints.
- **SmartPlay**: three new rule-based modes — Mood Arc (high-energy → wind-down), Deep Cut (skip openers and "Greatest Hits" comps), One Per Artist (max library breadth).
- **Branded launch screen**: Sun-Bleached Grooves splash matching the app icon (sunset gradient + black vinyl disc, no tonearm).
- **Performance**: throttle `currentTime` publish to ~2 Hz, gate the visualizer + display link on view visibility, pause the display link when the app backgrounds. Substantially fewer SwiftUI invalidations during normal playback.
- **Reliability**: fixed several Sendable / actor-isolation issues around background/foreground notification observers (no more compile-time isolation warnings; no spurious main-actor hops).
- Repeat-one indicator: subtle "1" badge on the repeat button when single-track loop is active.

### v0.3 — 2026-05-01
- Albums and Artists drill-downs work again (taps push into detail instead of looping).
- Album detail header redesigned: centered Winamp card with aligned PLAY / SHUFFLE.
- "PLAYER" row in BROWSE returns to the now-playing sheet; icon pulses with a live audio-level glow + 3-bar mini-VU.
- Skin picker overhauled: tap to cycle, long-press for a scrollable sheet, mirrored on the SwiftUI player.
- Four more bundled skins: Bento Classified, Crystal Display, Glass Factory, Luna Steel.
- Recent searches persisted (LRU, 10), shown when the search field is empty.
- README added.

### v0.2 — 2026-05-01
- EQ and Playlist panels now skin alongside the main player; switching skins recolors the entire now-playing sheet.
- Skin picker added to the SwiftUI (None) player.
- Mini player removed (auto-present-on-tap handles reopening the player).
- Fixed bogus read-only flag on every picked folder; on-drive index writes now work on writable locations.
- Folder delete added to Library → Folders view.

### v0.1
- Initial release.

## Feedback & feature requests

HarmonIQ is built in the open. **Have an idea, hit a bug, or just miss a feature from your favorite player?** Open an issue — that's the most direct way to land it on the roadmap:

- [🚀 Request a feature](https://github.com/LeoHChen/HarmonIQ/issues/new?labels=enhancement&title=Feature%20request%3A%20)
- [🐛 Report a bug](https://github.com/LeoHChen/HarmonIQ/issues/new?labels=bug&title=Bug%3A%20)
- [💬 Browse open issues / vote with 👍](https://github.com/LeoHChen/HarmonIQ/issues)

PRs are welcome too. The project's small, the architecture is documented in [`CLAUDE.md`](CLAUDE.md), and there's a smoke checklist in [`TESTING.md`](TESTING.md) to verify changes before merging.

## Acknowledgements

Skin parsing leans on classic Winamp 2.x specs and the file format documented at [archive.org's Winamp Skin Museum](https://archive.org/details/winampskins).
