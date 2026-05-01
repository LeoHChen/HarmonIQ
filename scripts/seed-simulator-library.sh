#!/usr/bin/env bash
# Seed a folder of audio files into the booted simulator's HarmonIQ Documents
# directory so it can be picked as a LibraryRoot via UIDocumentPicker.
#
# Usage:
#   scripts/seed-simulator-library.sh <source-folder> [destination-name]
#
# Example:
#   scripts/seed-simulator-library.sh ~/Music/TestAlbum FakeDrive
#
# After running, in the simulator: HarmonIQ → Settings → Add Music Folder →
# Browse → "On My iPhone" → HarmonIQ → <destination-name>.

set -euo pipefail

BUNDLE_ID="net.leochen.harmoniq"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <source-folder> [destination-name]" >&2
  exit 1
fi

SRC="$1"
DEST_NAME="${2:-$(basename "$SRC")}"

if [[ ! -d "$SRC" ]]; then
  echo "error: '$SRC' is not a directory" >&2
  exit 1
fi

# Confirm a simulator is booted.
if ! xcrun simctl list devices booted | grep -q "Booted"; then
  echo "error: no booted simulator. Boot one first (Xcode → Open Developer Tool → Simulator)." >&2
  exit 1
fi

# get_app_container needs the app to have been installed at least once.
if ! CONTAINER=$(xcrun simctl get_app_container booted "$BUNDLE_ID" data 2>/dev/null); then
  echo "error: app '$BUNDLE_ID' is not installed on the booted simulator." >&2
  echo "       Build & run HarmonIQ to the simulator first, then re-run this script." >&2
  exit 1
fi

DOCS="$CONTAINER/Documents"
DEST="$DOCS/$DEST_NAME"

mkdir -p "$DOCS"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "Seeded:"
echo "  from: $SRC"
echo "  to:   $DEST"
echo
echo "In the simulator's HarmonIQ → Settings → Add Music Folder, browse to"
echo "  On My iPhone → HarmonIQ → $DEST_NAME"
