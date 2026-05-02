# TESTING

Smoke checklist to run on a feature branch before merging. Should take **~10 minutes** end-to-end on a booted simulator with a seeded library.

If a section is irrelevant to your PR (e.g. you only touched skin loading), still run **A** (build) and **C** (playback) — those are the universal regression gates.

---

## Setup (once per simulator)

1. Boot iPhone 17 simulator (`xcrun simctl boot "iPhone 17"` or via Xcode).
2. Install HarmonIQ on it: `xcodebuild -scheme HarmonIQ -destination 'platform=iOS Simulator,name=iPhone 17' build` then run from Xcode once so the bundle ID gets registered.
3. Seed a music folder:
   ```bash
   scripts/seed-simulator-library.sh ~/Music/SomeAlbum FakeDrive
   ```
   The script copies into the simulator's `Documents/` so it's pickable via UIDocumentPicker.

---

## A. Build + launch (always run)

- [ ] `xcodegen generate` produces no diff in `project.pbxproj` after re-running.
- [ ] `xcodebuild build -scheme HarmonIQ -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug` is green with **zero new warnings** vs. main.
- [ ] App cold-launches to the Library tab without crashing.
- [ ] Launch screen renders the branded gradient + vinyl disc, not a flat-color flash.
- [ ] `git status` is clean (no accidental file leaks like `.DS_Store`, build artifacts).

---

## B. Library + drive flow

- [ ] Settings → **Add Music Drive…** → pick the seeded folder (`On My iPhone → HarmonIQ → FakeDrive`) → indexing runs to completion, no errors.
- [ ] All Tracks shows the seeded tracks with correct titles, artists, durations.
- [ ] Albums and Artists drill-downs work; tapping an album/artist opens a track list.
- [ ] Folders view shows the on-disk structure.
- [ ] Quit + relaunch app: drive is still listed, tracks appear without re-indexing.
- [ ] Settings → Reindex (the arrow.clockwise icon next to a drive): completes without errors.

---

## C. Playback (always run)

- [ ] Tap a track in All Tracks → now-playing sheet auto-presents and audio plays.
- [ ] Pause + Resume work in the active player (skinned or SwiftUI).
- [ ] Next / Previous advance through the queue.
- [ ] Drag the position slider, release — playback resumes at the new position; no audible glitch.
- [ ] Volume slider audibly changes loudness.
- [ ] Stop + restart: time resets to 0:00.
- [ ] Close the sheet and reopen via the player entry — same track, time roughly accurate.

---

## D. Shuffle + Repeat

- [ ] Shuffle on → tapping Next plays a non-sequential track.
- [ ] Shuffle off → Next plays the next sequential track.
- [ ] Repeat **off** → at end of queue, playback stops.
- [ ] Repeat **all** → at end of queue, wraps to first track.
- [ ] Repeat **one** → at end of track, same track replays.

---

## E. Skins

- [ ] Settings → Skins lists 9 bundled skins (Base-2.91, Bento-Classified, Crystal-Display, Glass-Factory, Green-Dimension-V2, Internet-Archive, Luna-Steel, MacOSXAqua1-5, TopazAmp1-2) plus any imported.
- [ ] Tapping a skin row updates the now-playing sheet on next open.
- [ ] In the skinned player: tap-to-cycle skin button advances to the next skin and shows its name.
- [ ] Long-press the cycle button → scrollable skin picker sheet.
- [ ] Import a `.wsz` from Files → it appears in the list and loads without crashing.
- [ ] **None** option (top of the list) falls back to the SwiftUI player on next sheet open.

---

## F. Playlists

- [ ] Create a playlist → it persists across app launches.
- [ ] Add a track via swipe → it appears in the playlist detail.
- [ ] Reorder tracks via drag handles (Edit mode).
- [ ] Remove a track via swipe.
- [ ] Delete a playlist via toolbar menu.
- [ ] Cross-device persistence: confirm `<DriveRoot>/HarmonIQ/playlists.json` is written for writable drives. (For the simulator-seeded folder, this is `<simulator-app-container>/Documents/FakeDrive/HarmonIQ/playlists.json`.)
- [ ] Favorite a track in the player (heart turns filled); the Playlists tab shows a pinned **Favorites** entry above the regular playlists. Tap it → favorited track is listed.
- [ ] Unfavorite from the player → heart unfills, count in Favorites decrements; if it was the last track the Favorites row remains (auto-managed) but shows `0 tracks`.
- [ ] Quit + relaunch → favorite state survives; the on-drive `playlists.json` includes `"kind": "favorites"` for the system playlist.
- [ ] With 2+ drives mounted, favorite tracks from each → two Favorites rows appear, each labelled with its drive name.

---

## G. Lock-screen + interruption

- [ ] With music playing, lock the device → lock-screen shows track info and artwork.
- [ ] Lock-screen play / pause / next / previous all control the app.
- [ ] Trigger Siri ("What time is it") then dismiss → music resumes without manual restart.
- [ ] Background the app for 30 s → return → playback continues, time display catches up.

---

## H. Smart Play

- [ ] Library → Smart Play lists all 12 modes (Pure Random, Artist Roulette, Genre Journey, Album Walk, Decade Shuffle, Freshly Added, Quick Hits, Long Player, Discovery Mix, Mood Arc, Deep Cut, One Per Artist).
- [ ] **Pure Random** plays a randomized queue.
- [ ] **Mood Arc**: queue starts with high-energy genres/titles (rock, dance, "anthem", short tracks) and ends with low-energy ones (ambient, classical, "intro", long tracks).
- [ ] **Deep Cut**: no track #1s and no tracks from albums whose name contains "Greatest Hits" / "Best Of" / "Compilation" / "Hits".
- [ ] **One Per Artist**: queue length equals the number of distinct artists in the library; each artist appears exactly once.
- [ ] At least one of (Album Walk, Artist Roulette, Discovery Mix) still builds a sensible queue and plays — regression check.

---

## I. Visualizer styles (SwiftUI player)

- [ ] Settings → Visualizer lists 8 styles (Spectrum, Oscilloscope, Plasma, Mirror, Radial Pulse, Particles, Fire, Starfield), each with a live preview thumbnail that animates.
- [ ] Tapping a row updates the checkmark and the now-playing visualizer matches on next open.
- [ ] In Now Playing, the visualizer header shows `VIS · <STYLE NAME>` and a `NEXT` cycle button.
- [ ] Tapping `NEXT` advances to the next style and shows a 1-second toast with the style name.
- [ ] Long-press OR double-tap on the visualizer surface cycles + toasts the same way.
- [ ] Quit and relaunch → the chosen style persists.
- [ ] With audio paused (silence), every style renders gracefully (Particles still drifts, Starfield slowly drifts, Spectrum decays — no frozen artifacts or crashes).
- [ ] Each style sustains roughly 30 fps with a percussive track playing (no obvious frame drops).

---

## What changed for *this* PR

The PR template adds a per-PR section listing the issue-specific tests from the linked issue's spec. Run those **in addition to** any of A–H that touch the same code paths. PRs that only change docs need only A.
