#!/usr/bin/env python3
"""fix-copyright.py: restore the exact copyright in a compiled OTF's CFF table.

fontmake/ufo2ft runs the copyright through a PostScript-name filter before
storing it in the CFF `Copyright` operator, which strips characters like
( ) / that appear in a standard OFL notice (e.g. the parenthesized URL). The
OpenType `name` table keeps the full string, but the redundant CFF copy comes
out mangled. This re-writes the CFF copy to match, verbatim.

The exact string is read from the UFO's fontinfo.plist (the source of truth),
so it always stays in sync with what you build. Only the OTF has a CFF table;
the TTF/WOFF/WOFF2 carry the copyright solely in `name` and need no fix.

Run it AFTER build.sh (re-run it after every rebuild, fontmake re-strips).

Usage:
  ./fix-copyright.py                                   # OTF + UFO defaults below
  ./fix-copyright.py output/StickOn-Regular.otf StickOn.ufo
"""
import os
import plistlib
import sys

from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
otf_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "output", "StickOn-Regular.otf")
ufo_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "StickOn.ufo")

# --- exact copyright, straight from the UFO source ------------------------
with open(os.path.join(ufo_path, "fontinfo.plist"), "rb") as fp:
    copyright = plistlib.load(fp).get("copyright")
if not copyright:
    sys.exit(f"error: no 'copyright' key in {ufo_path}/fontinfo.plist")

# --- patch the CFF Copyright operator -------------------------------------
f = TTFont(otf_path)
if "CFF " not in f:
    sys.exit(f"error: {otf_path} has no CFF table (nothing to fix; TTF/web "
             f"fonts carry copyright only in the name table)")
top = f["CFF "].cff.topDictIndex[0]
top.rawDict["Copyright"] = copyright
top.Copyright = copyright
f.save(otf_path)

# --- verify round-trip from disk ------------------------------------------
g = TTFont(otf_path)
cff = g["CFF "].cff.topDictIndex[0].rawDict.get("Copyright")
name0 = g["name"].getName(0, 3, 1, 0x409)
name0 = name0.toUnicode() if name0 else None
if cff != copyright or name0 != copyright:
    sys.exit(f"error: copyright mismatch after patch\n  CFF : {cff!r}\n"
             f"  name: {name0!r}\n  want: {copyright!r}")

print(f"ok: CFF copyright restored in {os.path.relpath(otf_path, HERE)}")
print(f"    {copyright}")
