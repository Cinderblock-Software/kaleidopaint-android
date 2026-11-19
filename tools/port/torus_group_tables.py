#!/usr/bin/env python3
# Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
"""
Translate the torus group tables of KaleidoPaintWallpaperGroup.swift to Kotlin.

The 17 `case .wpg…: return TorusGroup(…)` blocks are some 840 lines of matrix
entries.  Retyping them invites a wrong sign that no reviewer would spot, so
this script rewrites the Swift syntax into Kotlin syntax token by token and
leaves every number and every comment exactly as upstream wrote it.  It was
used once to produce the body of `WallpaperGroup.torusGroup` in
geometry/…/WallpaperGroup.kt, and is kept so the translation can be audited or
repeated when upstream changes.

    tools/port/torus_group_tables.py > /tmp/torus-groups.kt

The output is a raw property body, not a complete Kotlin compilation unit.
After replacing the generated property in WallpaperGroup.kt, run
`tools/format-kotlin.sh`. ktfmt expands the numeric layout and normalizes
trailing comment spacing; compare formatted output, not raw generator text.
Upstream sources remain untouched.

It refuses any line it does not recognise rather than passing it through.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "upstream/Source - SwiftUI/KaleidoPaint/KaleidoPaintWallpaperGroup.swift"

lines = SOURCE.read_text(encoding="utf-8").split("\n")

start = next(i for i, l in enumerate(lines) if l.strip() == "var torusGroup: TorusGroup {")
end = next(i for i, l in enumerate(lines) if l.startswith("//	Unit cells"))
block = lines[start:end]
while block and block[-1].strip() in ("", "}"):
    last = block.pop()
    if last.strip() == "}" and last.startswith("}"):
        break  # the brace that closes `enum WallpaperGroup`

CONSTRAINTS = re.compile(r"^(\s*)itsUnitCellShapeConstraints: \[(.*)\],$")
LIST_FIELD = re.compile(r"^(\s*)(itsElements|itsMirrorSegments|itsGyrationPoints|itsGlideReflectionSegments): \[(\],?)?$")
SEGMENT = re.compile(r"^(\s*)\(SIMD2<Double>\(([^)]*)\), SIMD2<Double>\(([^)]*)\)\)(,?)$")
POINT = re.compile(r"^(\s*)SIMD2<Double>\(([^)]*)\)(,?)$")
COLUMN = re.compile(r"^(\s*)SIMD3<Double>\(([^)]*)\)(,?)(\s*//.*)?$")
COLOR = re.compile(r"^(\s*)itsColor: (gColor(?:Rotated|Reflected)\d+)\)(,?)$")
CASE = re.compile(r"^(\s*)case \.(wpg\w+):$")

out = []
for number, line in enumerate(block, start=start + 1):
    stripped = line.strip()
    if stripped == "" or stripped.startswith("//"):
        out.append(line)
    elif stripped == "var torusGroup: TorusGroup {":
        out.append(line.replace("var torusGroup: TorusGroup {", "val torusGroup: TorusGroup by lazy {"))
    elif stripped == "switch self {":
        out.append(line.replace("switch self {", "when (this) {"))
    elif m := CASE.match(line):
        out.append(f"{m[1]}{m[2]} ->")
    elif stripped == "return TorusGroup(":
        out.append(line.replace("return TorusGroup(", "TorusGroup("))
    elif stripped == "TorusGroupElement(":
        out.append(line)
    elif stripped == "itsMatrix: simd_double3x3([":
        out.append(line.replace("itsMatrix: simd_double3x3([", "itsMatrix = Double3x3("))
    elif m := COLUMN.match(line):
        out.append(f"{m[1]}Double3({m[2]}){m[3]}{m[4] or ''}")
    elif stripped == "]),":
        out.append(line.replace("]),", "),"))
    elif m := COLOR.match(line):
        out.append(f"{m[1]}itsColor = {m[2]}){m[3]}")
    elif m := CONSTRAINTS.match(line):
        names = [n.strip().lstrip(".") for n in m[2].split(",") if n.strip()]
        inner = ", ".join(f"ShapeConstraint.{n}" for n in names)
        out.append(f"{m[1]}itsUnitCellShapeConstraints = setOf({inner}),")
    elif m := LIST_FIELD.match(line):
        closing = "" if m[3] is None else m[3].replace("]", ")")
        out.append(f"{m[1]}{m[2]} = listOf({closing}")
    elif m := SEGMENT.match(line):
        out.append(f"{m[1]}Pair(Double2({m[2]}), Double2({m[3]})){m[4]}")
    elif m := POINT.match(line):
        out.append(f"{m[1]}Double2({m[2]}){m[3]}")
    elif stripped in ("],", "]"):
        out.append(line.replace("]", ")"))
    elif stripped in (")", "}"):
        out.append(line)
    else:
        sys.exit(f"line {number} not recognised: {line!r}")

sys.stdout.write("\n".join(out) + "\n")
