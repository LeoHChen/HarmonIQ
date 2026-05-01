# HarmonIQ

A SwiftUI music player for iPhone and iPad, styled after the classic Winamp era. Plays audio files straight off any folder you can mount in Files — including USB drives — and ships its index alongside the music so the same drive works on any device without re-scanning.

## Features

- **Drive-portable library.** Tracks, playlists, and artwork live in a `HarmonIQ/` folder on the drive itself. Plug the same drive into another iPhone and your library shows up unchanged.
- **External-drive friendly.** Pick any folder Files can see (USB-C drives, SMB shares, iCloud Drive, on-device storage). Read-only locations are supported via a sandbox shadow store.
- **Background playback** with full lock-screen / Control Center / CarPlay-style controls via `MPNowPlayingInfoCenter`.
- **Winamp skins.** Drop classic `.wsz` files in via the importer; bundled skins ship with the app. Skinned main window, equalizer, and playlist all render from the original sprites.
- **SmartPlay queues.** Pure Random, Artist Roulette, Album Walk, Decade Shuffle, Discovery Mix, and more — built on top of your library.
- **Live visualizer.** 24-band spectrum, oscilloscope, and plasma reconstructions driven by AVAudioPlayer's metering.

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

## Acknowledgements

Skin parsing leans on classic Winamp 2.x specs and the file format documented at [archive.org's Winamp Skin Museum](https://archive.org/details/winampskins).
