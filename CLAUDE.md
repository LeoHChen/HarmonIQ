# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & run

iOS 16+ SwiftUI app. Targets iPhone and iPad (`TARGETED_DEVICE_FAMILY: "1,2"`), Swift 5.9.

```bash
# This machine has Xcode installed but `xcode-select` may point at CommandLineTools.
# Prefix xcodebuild with DEVELOPER_DIR if `xcodebuild -list` errors.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project HarmonIQ.xcodeproj -scheme HarmonIQ \
    -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Available destinations: `xcodebuild -showdestinations -project HarmonIQ.xcodeproj -scheme HarmonIQ`.

There is no test target and no lint config. Build is the only check.

### XcodeGen

`project.yml` is the source of truth — the `.pbxproj` is generated. `xcodegen` is installed at `/opt/homebrew/bin/xcodegen`. **If you add, rename, or delete files, regenerate** rather than hand-editing `project.pbxproj`:

```bash
xcodegen generate
```

`Info.plist` properties (background audio mode, `NSAppleMusicUsageDescription`, `UIFileSharingEnabled`, supported orientations) are declared inline in `project.yml`, not in a separate plist file.

### MCP

`.mcp.json` registers the `XcodeBuildMCP` server (`npx xcodebuildmcp@latest`). When that MCP is available, prefer its build/simulator tools over shelling out to `xcodebuild`.

## Architecture

### App composition

`HarmonIQApp` instantiates four `@MainActor` singletons and injects them as `@EnvironmentObject`:

- `LibraryStore.shared` — aggregates tracks/playlists across all currently-mounted drives. Locally persists only `roots.json` (the device's bookmarks). Tracks and playlists themselves live on the drives.
- `AudioPlayerManager.shared` — `AVAudioPlayer` wrapper plus queue/shuffle/repeat state and live audio levels.
- `MusicIndexer.shared` — scans a `LibraryRoot` and writes the index into the drive's `HarmonIQ/` folder.
- `NowPlayingManager.shared` — bridges `MPRemoteCommandCenter` (lock screen / control center) to `AudioPlayerManager` callbacks. Activated once at launch from `HarmonIQApp.body`'s `.task`.

`HarmonIQApp.init()` also configures `AVAudioSession` (`.playback`) and global `UITabBar`/`UINavigationBar` appearance to match the Winamp theme. `UITableView`/`UICollectionView` backgrounds are forced clear so `WinampTheme.appBackground` shows through SwiftUI `List`/`ScrollView`.

### Persistence model — drive is the source of truth

Every drive carries its own `HarmonIQ/` folder at the drive root:

```
<DriveRoot>/HarmonIQ/
  library.json       # tracks for this drive (DriveLibraryStore.DriveLibraryFile)
  playlists.json     # playlists owned by this drive (DriveLibraryStore.DrivePlaylistsFile)
  Artwork/<sha1>.jpg
```

`DriveLibraryStore` (`HarmonIQ/Persistence/DriveLibraryStore.swift`) is the only thing that touches those files. Its DTOs (`DriveTrack`, `DrivePlaylist`) intentionally **omit per-device fields** (`rootBookmarkID`, file bookmarks). Those are rebound to the *current* device's `LibraryRoot.id` when reading. This is what makes the same drive work on any iPhone without reindexing.

`Track.stableID` is **drive-relative** — `sha1(relativePath)` only, no `rootID` mixed in — so playlists from another iPhone resolve against tracks on this iPhone.

The app sandbox holds only:
- `Application Support/HarmonIQ/roots.json` — the device's `LibraryRoot` list (display name, security-scoped bookmark, last-indexed timestamp).
- `Application Support/HarmonIQ/Artwork/` — a local mirror of every drive's artwork, populated when a drive is loaded (so views and `MPNowPlayingInfo` can read images without keeping a security-scoped resource open).

Loading flow on app launch (`LibraryStore.loadFromDisk`):
1. Read `roots.json`.
2. For each root, `loadDriveData(for:)` → resolve bookmark → start scope → `DriveLibraryStore.loadLibrary` + `loadPlaylists` + `mirrorArtworkToLocalCache` → stop scope.
3. If a drive is offline, its tracks/playlists are absent from the in-memory state; the root remains so the user can reconnect later.

Adding a drive that already has a `HarmonIQ/library.json` adopts it without reindexing — `SettingsView.addRoot` only kicks off `MusicIndexer.index(root:)` when no existing index loaded.

Playlists are owned by exactly one drive (`Playlist.rootBookmarkID`, in-memory only). `LibraryStore.createPlaylist` defaults to the first root; tradeoff: a playlist can only reference tracks from its owning drive (cross-drive playlists are not supported).

### Library access model — security-scoped bookmarks

The user picks any folder visible in Files (including USB drives) via `UIDocumentPicker`. That folder URL is stored as a security-scoped bookmark on a `LibraryRoot` (`bookmark: Data`). Every time we touch files inside a root we must:

1. Resolve the bookmark with `URL(resolvingBookmarkData:bookmarkDataIsStale:)`.
2. Call `startAccessingSecurityScopedResource()` and balance with `stop…`.
3. Refresh the bookmark if `stale == true`.

`BookmarkStore` provides `withAccess`/`withAccessReportingStale` helpers. `MusicIndexer.runIndex` and `AudioPlayerManager.playCurrent` both follow this dance — `AudioPlayerManager` keeps `accessRoot` open across the lifetime of the currently playing track (released in `releaseAccessRoot`).

`Track.stableID` is `sha1(relativePath)` (drive-relative). Surviving re-index keeps playlists and "recently played" intact, and the same hash on any device means the on-drive index/playlists are portable.

### Indexing concurrency pattern

`MusicIndexer.index()` spawns a `Task.detached` running `runIndex` (a `static` nonisolated function) so file walking and metadata extraction never block the main actor. UI state (`isIndexing`, `progress`, `statusMessage`) is updated via `await MainActor.run`. The detached task respects `Task.isCancelled` between files and at scan time. Artwork is deduplicated by `sha1(albumArtist|album)` and written once per album under `LibraryStore.shared.artworkDirectory`.

### Audio levels → visualizer

`AudioPlayerManager` runs a 30Hz `CADisplayLink` while playing. Each tick:
- updates `currentTime`,
- reads `averagePower` / `peakPower` per channel and publishes a normalized `levels: SIMD2<Float>` (avg, peak),
- forwards elapsed time to `NowPlayingManager`.

`Views/Visualizers.swift` consumes `player.levels` inside a `TimelineView(.animation)` Canvas. `VisualizerEngine` (`@MainActor`) synthesizes 24 spectrum bands, a 128-sample oscilloscope buffer, and a plasma phase from the single `levels` value — the engine is a *believable-looking* reconstruction, not real FFT.

**Important constraint**: drawing helpers (`drawSpectrum`, `drawOscilloscope`, `drawPlasma`) are `@MainActor`-annotated because they read main-actor-isolated state on `VisualizerEngine`. New helpers that touch the engine must keep this annotation.

### SmartPlay

`SmartPlay.swift` defines `SmartPlayMode` (Pure Random, Artist Roulette, Album Walk, Decade Shuffle, Discovery Mix, etc.) and `SmartPlayBuilder.buildQueue` — pure functions producing an ordered `[Track]` from a pool. `playSmart(mode:from:)` disables manual shuffle so the curator's order is preserved. `Discovery Mix` weights against `sessionPlayedIDs` (in-memory only — does not persist across launches).

### Theming

`Views/WinampTheme.swift` is the central design system: gunmetal panel gradient, lime "LCD" colors, bevel accents, `lcdFont(size:)` for monospaced readouts, plus `BevelPanel`/`LCDPanel` view modifiers (`.bevelPanel(corner:)`, `.lcdPanel()`). Use these instead of hand-rolling backgrounds. Phosphor accent color is also reflected in `Assets.xcassets/AccentColor`.

`design/PHILOSOPHY.md` documents the icon's visual direction ("Sun-Bleached Grooves"). `design/render_icon.py` generates the app icon PNG.

## Conventions worth knowing

- All shared state lives on `@MainActor`. Heavy work uses `Task.detached` + `await MainActor.run` to hop back; do not weaken actor isolation to "fix" a warning — the visualizer bug fixed in commit `c7ddb9c` was exactly that mistake.
- `Track` equality and hashing use `stableID`, not `id`. Don't rely on `id` for deduplication.
- Prefer `Track.displayTitle` / `displayArtist` / `displayAlbum` over the optional raw fields when rendering — they apply the "Unknown Artist" / filename fallbacks consistently.
- `LibraryStore` writes happen on a private serial `DispatchQueue` via `saveLibrary()` / `savePlaylists()`. Read-modify-write must stay on the main actor; only the file I/O hops off.
- Background audio works because `UIBackgroundModes: [audio]` is set in `project.yml` *and* `AVAudioSession` is `.playback`. Removing either silently breaks lock-screen playback.
