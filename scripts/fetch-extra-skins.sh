#!/usr/bin/env bash
# fetch-extra-skins.sh — download .wsz Winamp skins into the bundled
# Resources/Skins/ folder.
#
# Reads a newline-separated list of URLs from stdin. Each URL must point at
# a .wsz file. Files are saved by their last path component, deduped by
# filename, and the user is reminded to regenerate the Xcode project so
# the new skin gets bundled into the app.
#
# Usage:
#   ./scripts/fetch-extra-skins.sh <<EOF
#   https://example.com/skin/CoolSkin.wsz
#   https://example.com/skin/Another.wsz
#   EOF
#
# Or feed a file:
#   ./scripts/fetch-extra-skins.sh < urls.txt
#
# Verify each source's license before redistributing.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKIN_DIR="$REPO_ROOT/HarmonIQ/Resources/Skins"

if [ ! -d "$SKIN_DIR" ]; then
  echo "error: skin directory not found at $SKIN_DIR" >&2
  exit 1
fi

added=0
skipped=0

while IFS= read -r url || [ -n "$url" ]; do
  url="$(echo "$url" | tr -d '\r' | xargs)"
  case "$url" in
    ""|\#*) continue ;;
  esac
  filename="$(basename "${url%%\?*}")"
  case "$filename" in
    *.wsz) ;;
    *)
      echo "skip: $url (not a .wsz)" >&2
      skipped=$((skipped+1))
      continue
      ;;
  esac
  out="$SKIN_DIR/$filename"
  if [ -e "$out" ]; then
    echo "skip: $filename (already exists)"
    skipped=$((skipped+1))
    continue
  fi
  echo "fetch: $url"
  if curl -fL --retry 2 -o "$out" "$url"; then
    added=$((added+1))
  else
    echo "  failed: $url" >&2
    rm -f "$out"
  fi
done

echo
echo "added=$added skipped=$skipped"
if [ "$added" -gt 0 ]; then
  echo
  echo "next: re-run \`xcodegen generate\` (and rebuild) so the new skins"
  echo "are picked up by the app bundle."
fi
