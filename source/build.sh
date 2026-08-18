#!/usr/bin/env bash
#
# build.sh — compile StickOn.ufo into OTF, TTF, WOFF, and WOFF2.
#
# Produces a strictly monospaced font (every glyph advance = 600), including
# a fix for the auto-generated .notdef, which ufo2ft otherwise emits at a
# different width. Outputs land in ./output/.
#
# Usage:
#   ./build.sh                # build from StickOn.ufo
#   ./build.sh MyFont.ufo     # build from a different UFO
#
# On first run it creates a local Python venv (.venv/) and installs the
# needed tools. Subsequent runs reuse it.

set -euo pipefail

# --- Config ---------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UFO="${1:-$HERE/StickOn.ufo}"
OUT="$HERE/output"
VENV="$HERE/.venv"
MONO_WIDTH=600            # the single advance width all glyphs must have

# --- Sanity checks --------------------------------------------------------
if [[ ! -d "$UFO" ]]; then
  echo "error: UFO not found: $UFO" >&2
  exit 1
fi

# --- Python environment ---------------------------------------------------
if [[ ! -x "$VENV/bin/python" ]]; then
  echo ">> creating venv at $VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  # fontmake pulls in fonttools + ufo2ft; brotli is needed for WOFF2.
  "$VENV/bin/pip" install --quiet fontmake brotli
fi
PY="$VENV/bin/python"
FONTMAKE="$VENV/bin/fontmake"

# --- Base name derived from the UFO --------------------------------------
BASENAME="$(basename "$UFO" .ufo)-Regular"
mkdir -p "$OUT"

# --- Compile OTF and TTF --------------------------------------------------
echo ">> building OTF"
"$FONTMAKE" -u "$UFO" -o otf --output-path "$OUT/$BASENAME.otf"
echo ">> building TTF"
"$FONTMAKE" -u "$UFO" -o ttf --output-path "$OUT/$BASENAME.ttf"

# --- Fix .notdef advance, then spin out the web fonts ---------------------
echo ">> fixing .notdef width and generating WOFF/WOFF2"
"$PY" - "$OUT" "$BASENAME" "$MONO_WIDTH" <<'PYEOF'
import sys
from fontTools.ttLib import TTFont

out, base, mono = sys.argv[1], sys.argv[2], int(sys.argv[3])

# Force .notdef to the monospace advance in both binary sources.
for ext in ("otf", "ttf"):
    path = f"{out}/{base}.{ext}"
    f = TTFont(path)
    _, lsb = f["hmtx"][".notdef"]
    f["hmtx"][".notdef"] = (mono, lsb)
    f.save(path)

# Build WOFF and WOFF2 from the corrected TTF.
src = TTFont(f"{out}/{base}.ttf")
for flavor, ext in (("woff", "woff"), ("woff2", "woff2")):
    src.flavor = flavor
    src.save(f"{out}/{base}.{ext}")

# Verify: report the set of advance widths (should be just {mono}).
check = TTFont(f"{out}/{base}.otf")
widths = {w for w, _ in (check["hmtx"][g] for g in check.getGlyphOrder())}
print(f"   advance widths in output: {widths}")
if widths != {mono}:
    sys.exit(f"error: expected all advances == {mono}, got {widths}")
PYEOF

echo ">> done. Files in $OUT:"
ls -1 "$OUT"
