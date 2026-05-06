# Tag-writing library selection (issue #113)

Research brief feeding the per-track ID3 edit work in #114.
**No SPM dependencies are added by this brief** — that's #114's job.
This brief picks the library, justifies the pick, and sketches the
integration.

## 1. Format landscape

What HarmonIQ currently indexes
(`HarmonIQ/Indexer/MetadataExtractor.swift:19`):

```swift
static let supportedExtensions: Set<String> =
    ["mp3", "m4a", "flac", "wav", "aiff", "aif", "aac"]
```

Approximate share of a typical user library (rough Western-centric
estimates from public Plex / Roon community telemetry; tighten later
if we add real telemetry):

| Format    | Container | Tag system          | Approx. share |
| --------- | --------- | ------------------- | ------------- |
| mp3       | MP3       | ID3v2.3 / v2.4      | 50–70 %       |
| m4a / aac | MP4 / ISO | iTunes-style atoms  | 20–40 %       |
| flac      | FLAC / Ogg| Vorbis comments     | 5–15 %        |
| wav       | RIFF      | INFO chunks / ID3   | <2 %          |
| aiff/aif  | AIFF      | ID3 in `ID3 ` chunk | <1 %          |

The Tier 1 edit sheet in #114 has to write `title / artist / album /
albumArtist / trackNumber / year / genre` round-trip-safely in at
least mp3 + m4a. flac is the next must-have. wav/aiff are nice-to-have
and can fall back to "read-only" with a clear message in the edit
sheet.

The current read path (`MetadataExtractor`) goes through `AVURLAsset
.commonMetadata` + per-format `loadMetadata(for:)`. AVFoundation reads
all of the above; **it does not write any of them** — there's no
public API for tag write-back via AVFoundation, which is why we need a
third-party writer.

## 2. Candidate matrix

| Library                           | License             | Formats (write)            | Last release / activity         | Swift / iOS support           | API style                         | Write semantics       | Binary impact   |
| --------------------------------- | ------------------- | -------------------------- | ------------------------------- | ----------------------------- | --------------------------------- | --------------------- | --------------- |
| **`ID3TagEditor`** (chicio)       | MIT                 | mp3 (ID3v2.2/2.3/2.4)      | v5.5.0 (Jan 2026); Swift 6      | Pure Swift, SPM, iOS-friendly | `ID3Tag` builder + `read`/`write` | Read whole, edit, write whole (in-place) | Small (~tens of KB) |
| **`SwiftTaggerID3`** (NCrusher74) | Apache-2.0          | mp3 (ID3v2.2/2.3/2.4)      | 405 commits, last tag old (~2021) | Pure Swift, SPM            | Frame-by-frame                    | Read, edit, write whole | Small         |
| **TagLib via wrapper**            | LGPL-2.1 / MPL-1.1 (dual) | Everything (mp3, m4a, flac, ogg, wav, aiff, opus, ape, …) | C++ project still active; **iOS Swift wrappers stale** (TagLibIOS 2018, TagLibKit 2020) | Needs Obj-C++ shim; SPM via wrapper | C++ API           | Whole-file read/edit/write | Large (~MBs)  |
| **`SFBAudioEngine`** (sbooth)     | MIT                 | "most formats" (vague — flagship is decode/play, write surface poorly documented) | v0.12.1 (Feb 2026); active     | iOS 15+, SPM, Obj-C++ core  | `SFBAudioFile` metadata type      | Read, edit, write whole | Medium (audio engine bundled) |
| **AVFoundation only (current)**   | Apple SDK           | None (read-only)           | n/a                             | Built-in                      | `AVURLAsset.commonMetadata`       | Read only             | Zero            |
| **Hand-rolled writer**            | Our own             | Whatever we implement      | n/a                             | Pure Swift                    | n/a                               | We define             | Zero            |

### Notes on each row

- **`ID3TagEditor`**: Actively maintained, MIT, pure-Swift, recent
  Swift 6 support, recent release in January. Confirms ID3v2.2 /
  v2.3 / v2.4 read+write. The catch: **mp3 only**. m4a and flac need
  something else.
- **`SwiftTaggerID3`**: Same scope as `ID3TagEditor` (mp3 only) but
  noticeably less active. Apache-2.0 license is fine. No reason to
  pick it over `ID3TagEditor`.
- **TagLib via Swift wrapper**: TagLib itself is the gold standard
  (used by Plex, Mixxx, Strawberry, etc.) and would solve every
  format in one go. The catch: **dual LGPL-2.1 / MPL-1.1**. LGPL on
  iOS is workable (static linking is fine if you publish enough to
  let users relink — this is the standard FOSS-on-iOS interpretation
  but not airtight), and MPL is friendlier — but App Store
  attribution + the LGPL-on-iOS ambiguity is a real friction point
  for a 1-developer shop. The bigger problem is the *Swift wrappers*
  are abandoned — TagLibIOS last touched 2018, TagLibKit 2020. Any
  modern iOS-targeted use would mean writing or maintaining our own
  Obj-C++ shim against the live TagLib C++ source. That's not a v1.2
  scope.
- **`SFBAudioEngine`**: Active, MIT, broad format support, iOS 15+.
  The downside is it's a big audio-decode/encode engine — metadata
  read/write is one feature among many. Its README acknowledges
  metadata is "writable for most formats" without naming them, which
  is exactly the wrong level of detail for a library you're picking
  to be your tag-writer. Pulling it in for tag writing alone bundles
  a lot of code (and runtime + size impact) for a feature we
  fundamentally do not need.
- **AVFoundation only**: Apple has shipped no public tag-write API.
  `AVAssetExportSession` can rewrite metadata for QuickTime / MP4
  containers (m4a only) but mangles non-iTunes atoms and doesn't
  touch mp3 or flac. Not a real option.
- **Hand-rolled**: 100 % under our control, zero dependency, biggest
  maintenance burden by orders of magnitude. ID3v2 alone is a
  multi-page spec (frame headers, sync-safe integers, unsynchronised
  encoding, padding behaviors); MP4 atoms have their own
  iTunes-specific quirks (`----` user-defined atoms, the `meta`
  atom's required hdlr child, etc.). Punching this in for a v1.2
  feature is a lot of risk for no reuse — eventually we'd want
  somebody else's tested writer anyway.

## 3. Recommendation

**Primary: `ID3TagEditor` for mp3.** **Fallback / next steps: see
section 4 for m4a + flac.**

`ID3TagEditor` is the only candidate that scores well on every axis
HarmonIQ cares about: MIT license (no App Store / static-linking
worry), pure Swift (the Obj-C++ bridges in TagLib wrappers add a
real maintenance tax that's not justified for our scope), recently
released (Jan 2026, with active Swift 6 support), small surface area
(its `ID3Tag` value type is essentially what our edit sheet's data
model would look like anyway), in-place file write (we hand it the
file path inside `BookmarkStore.withAccess`, it returns when the
write is done — clean security-scope semantics).

The cost of picking it: we ship Tier 1 of issue #114 with **mp3-only
edit support** and a "this format isn't editable yet" empty state for
m4a / flac / wav / aiff. Given that mp3 is 50–70 % of typical
libraries, that ships meaningful value while leaving the rest for a
follow-up.

We deliberately reject TagLib for v1.2 because (a) the Swift
wrappers are abandoned, (b) writing our own wrapper isn't justified
for one feature, and (c) the LGPL ambiguity on iOS is a foot-gun for
a single-developer App Store project. If the user's library is
predominantly m4a (which the ratio above suggests is plausible), the
right next step is **not** TagLib — see §4.

## 4. Fallback / coverage gaps

The primary recommendation only handles mp3. Here's the path to fill
in the rest, in priority order:

### m4a — second priority, separate library

Two viable paths:

1. **Hand-rolled MP4 atom writer for the iTunes-style metadata
   atoms** we actually edit (`©nam`, `©ART`, `©alb`, `aART`, `trkn`,
   `©day`, `©gen`). MP4 metadata is bounded enough that a small,
   purpose-built writer is realistic — maybe 200–400 lines, with
   `AVURLAsset` continuing to handle the read side. Big win on
   binary size + license cleanliness. Real maintenance cost: any
   iTunes weirdness (sort-name atoms, free-space handling, the
   required `meta` → `hdlr` → `ilst` chain) is on us forever.
2. **Pull in `SFBAudioEngine` strictly for m4a write**, with the
   understanding that we're using ~5 % of its surface area. Cleaner
   but heavier. If we go this way, gate the import behind `#if
   canImport(SFBAudioEngine)` so the v1.2 PR can ship without it
   and add it as a follow-up.

The implementation issue for m4a (sibling to #114) should pick
between these based on a small spike — write a one-trip
"read-modify-write" test for both approaches and compare diffs of
the original vs. modified file. Whichever one preserves the
non-edited atoms byte-for-byte is the winner.

### flac — third priority

Vorbis comments are simpler than ID3v2 (no frame headers, no
sync-safe integers). A purpose-built flac writer is plausible (~150
lines) and worth the trade-off vs. pulling TagLib for one format.

### wav / aiff — read-only is fine

`<2 %` of typical libraries. The Tier 1 edit sheet should refuse
edits on these formats with an explicit message ("Editing tags in
WAV / AIFF files isn't supported yet"). No code-bridge cost.

## 5. Implementation sketch for issue #114

The shape of the writer should match the `BookmarkStore.withAccess`
contract that the rest of the codebase already follows (CLAUDE.md:
"every drive access goes through `BookmarkStore.withAccess`"). I'd
expect a new file `HarmonIQ/Indexer/TagWriter.swift`:

```swift
/// Writes tag edits back to a single audio file. Format dispatch is
/// internal — callers pass a `Track` and an `EditedTags` value type.
@MainActor
final class TagWriter {
    enum WriteError: Error {
        case formatNotEditable(String)   // "wav", "aiff", "ogg", …
        case readFailed(underlying: Error)
        case writeFailed(underlying: Error)
        case bookmarkResolveFailed
    }

    struct EditedTags {
        var title: String?
        var artist: String?
        var album: String?
        var albumArtist: String?
        var trackNumber: Int?
        var year: Int?
        var genre: String?
    }

    /// Writes `edits` to the file backing `track` and updates the
    /// matching row in `LibraryStore` in-memory. Persists the
    /// drive's library.json on success. Run this off the main actor
    /// (Task.detached); the @MainActor annotation here is for the
    /// LibraryStore handoff after the write completes.
    func write(_ edits: EditedTags, to track: Track,
               in root: LibraryRoot) async throws -> Track
}
```

### Flow inside `write`

1. Resolve the root's bookmark via `BookmarkStore.withAccess` (or
   the equivalent helper from `LibraryStore.withDriveAccess` — we
   probably want to expose a small public version of that for the
   writer).
2. Inside the scope, dispatch to format:
   - `mp3` → `ID3TagEditor.write(...)` against the file URL.
   - everything else → `throw WriteError.formatNotEditable(...)`
     (Tier 1 ships with this gap; #4-style follow-up issues fill
     them in).
3. After the writer returns, **re-extract metadata via the existing
   `MetadataExtractor`** so the in-memory `Track` reflects exactly
   what's on disk (don't trust the edits dict — round-trip through
   the same reader the indexer uses, so we can't drift).
4. Hop to `MainActor.run` and patch the matching track in
   `LibraryStore.tracks` in place. Call
   `LibraryStore.replaceTracks(forRoot:with:)` with the patched
   per-drive slice; that already rewrites `library.json` on the
   owning drive via the existing `DriveLibraryStore.writeLibrary`
   path. **No full re-index.**
5. Return the new `Track` so the edit sheet can confirm.

### Round-trip safety

`ID3TagEditor` reads the whole tag, lets you mutate, and writes
back. **The library round-trips frames it doesn't know about** —
which is what we need for #114's "Round-trip safety: writing back
unchanged tags must not corrupt the file" requirement. Cite this in
the implementation PR's testing notes.

### Security-scope dance — concrete

```swift
let url: URL = try BookmarkStore.withAccess(to: root.bookmark) {
    rootURL in
    let fileURL = rootURL.appendingPathComponent(
        track.relativePath.joined(separator: "/"))
    let editor = ID3TagEditor()
    var tag = try editor.read(from: fileURL.path) ?? ID3Tag(...)
    // apply edits to tag
    try editor.write(tag: tag, to: fileURL.path)
    return fileURL
}
```

`ID3TagEditor` takes file paths (not URLs), which is fine —
inside `withAccess`'s closure we have a resolved `URL`, and
`url.path` gives us the path the library expects. The closure stays
synchronous; `withAccess` handles
`startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource`
balanced around it.

### What this brief is NOT defining

- The **edit-sheet UI** — that's #114's job, not the library
  research.
- **Tier 2 AI suggestions** — that's the second PR of #114, gated
  behind `AIProvider.anyAvailable` per #102. Doesn't affect library
  choice; the writer doesn't care where the proposed string came
  from.
- **Bulk edit / library cleanup** — different issue. The
  per-track writer is the substrate; bulk just calls it in a loop
  with a progress meter. No library change needed.

## 6. Summary

| Question                               | Answer                                                                |
| -------------------------------------- | --------------------------------------------------------------------- |
| Pick                                   | `ID3TagEditor` (chicio, MIT, Swift, mp3-only) for v1.2 Tier 1 mp3.    |
| What ships in #114 Tier 1              | mp3 edit sheet wired through `TagWriter`. Other formats: clear "not yet supported" message. |
| What ships in a follow-up              | m4a writer (hand-rolled atom writer or `SFBAudioEngine`, decided by a spike). flac writer if appetite. |
| What we explicitly defer               | TagLib bridge. Hand-rolling all formats from scratch.                 |
| New SPM deps in the v1.2 fix PR         | `ID3TagEditor` (one).                                                |
| New SPM deps in this brief             | None. (#113 is research-only.)                                        |
