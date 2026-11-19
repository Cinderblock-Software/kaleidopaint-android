#!/usr/bin/env python3
# Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
"""
Check that the Kotlin translations kept upstream's comments.

Upstream's comments are much of the value of a translation.  For every upstream file that has been ported in full, this lists the
comment text that appears in the Swift file but nowhere in its Kotlin
counterpart.  Comments are compared with whitespace collapsed, so
re-indenting is not a difference; rewording is.

    tools/port/comment_audit.py          # summary, exits 1 if anything is missing
    tools/port/comment_audit.py -v       # also print each missing comment

The per-file header is expected to differ (the port's licence header replaces
it).  Expected differences are listed in EXPECTED below, with the reason, so
that anything else stands out.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SWIFT = ROOT / "upstream/Source - SwiftUI/KaleidoPaint"
KOTLIN = ROOT / "geometry/src/main/kotlin/com/cinderblocksoftware/kaleidopaint/geometry"

PORTED = {
    "KaleidoPaintWallpaperGroup.swift": "WallpaperGroup.kt",
    "KaleidoPaintCoordinateSystems.swift": "CoordinateSystems.kt",
    "KaleidoPaintUnitCellPlacement.swift": "UnitCellPlacement.kt",
    "KaleidoPaintCubicSpline.swift": "CubicSpline.kt",
    "KaleidoPaintCurve.swift": "Curve.kt",
    "KaleidoPaintDot.swift": "Dot.kt",
    "KaleidoPaintBrushstroke.swift": "Brushstroke.kt",
    "KaleidoPaintDrawingElement.swift": "DrawingElement.kt",
}

# comment text (whitespace collapsed) -> why it is allowed to be absent
EXPECTED = {
    "© 2026 by Jeff Weeks": "file header, replaced by the port's licence header",
    "See TermsOfUse.txt": "file header, replaced by the port's licence header",
}


def comments(text):
    """Comment texts in a source file, whitespace collapsed, markers removed."""
    found = []
    for line in text.split("\n"):
        i = line.find("//")
        if i < 0:
            continue
        body = re.sub(r"\s+", " ", line[i + 2:]).strip()
        if body and not body.startswith("MARK:"):
            found.append(body)
    return found


def main():
    verbose = "-v" in sys.argv
    unexpected = 0
    for swift_name, kotlin_name in PORTED.items():
        swift = (SWIFT / swift_name).read_text(encoding="utf-8")
        kotlin = (KOTLIN / kotlin_name).read_text(encoding="utf-8")
        have = set(comments(kotlin))
        # A trailing comment may have moved to a line of its own, or the other
        # way round, so also accept a comment found anywhere in the Kotlin text.
        flat = re.sub(r"\s+", " ", kotlin)
        wanted = [c for c in comments(swift) if c != swift_name]
        missing = [c for c in wanted if c not in have and c not in flat]
        allowed = [c for c in missing if EXPECTED.get(c)]
        surprising = [c for c in missing if not EXPECTED.get(c)]
        unexpected += len(surprising)
        print(f"{swift_name}: {len(wanted)} comment lines, "
              f"{len(wanted) - len(missing)} kept, {len(allowed)} expected differences, "
              f"{len(surprising)} missing")
        if verbose or surprising:
            for c in surprising:
                print(f"    MISSING  {c}")
        if verbose:
            for c in allowed:
                print(f"    expected {c}   ({EXPECTED[c]})")
    return 1 if unexpected else 0


if __name__ == "__main__":
    sys.exit(main())
