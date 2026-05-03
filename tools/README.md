# tools/

Offline maintenance scripts for HarmonIQ. These run from a Mac terminal with
the music drive mounted at any path — they operate on the on-drive
`HarmonIQ/library.json` directly, no app required.

## library-doctor.swift (issue #88)

Diagnose and repair a drive whose Albums view is bloated with duplicates.

```bash
# Diagnose — read-only, prints duplicate stableID counts and compilation candidates.
swift tools/library-doctor.swift --report  /Volumes/Music

# Collapse rows that share a stableID (sha1(relativePath)). Keeps the first.
# Writes back to library.json atomically.
swift tools/library-doctor.swift --dedupe  /Volumes/Music

# Nuke library.json so the next app launch reindexes from scratch.
# Playlists at HarmonIQ/playlists.json are left alone — they reference tracks
# by stableID, which a clean reindex regenerates.
swift tools/library-doctor.swift --rebuild /Volumes/Music
```

The path argument is the **drive root you picked in HarmonIQ** (the parent of
`HarmonIQ/`), not the `HarmonIQ/` folder itself.

### When to use which mode

| Symptom | Mode |
| --- | --- |
| "I want to see what's going on before touching anything." | `--report` |
| Same track appears twice in the same album. | `--dedupe` |
| Albums look fragmented (one "1995 Grammy Nominees" per artist) and the in-app Rebuild action isn't enough. | `--rebuild` |

The in-app *Settings → Maintenance → Rebuild library* action is the same
operation as `--rebuild`, just triggered from the phone. Use the script when
the device isn't handy or when you want to script bulk maintenance across
several drives.

### Limitations

- Read-only roots (where the index lives in the app sandbox, not on the
  drive) aren't reachable from this script — Settings is the only path.
- Compilation grouping in the in-app Albums view is purely a UI fold-up
  (issue #88); `--report` flags compilation candidates but doesn't
  rewrite anything. Use it as a sanity check.
