#!/bin/sh
# Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
#
# Builds the Swift reference harness from upstream's own, unmodified source,
# runs it, and writes what the Kotlin unit tests compare against:
#
#     tools/reference/build.sh
#     -> geometry/src/test/resources/reference.txt            reference values
#     -> geometry/src/test/resources/drawings/*.kaleidopaint  drawing files
#     -> geometry/src/test/external-drawings/reference.txt    (only if real
#        drawings have been fetched there; that directory is not in git)
#
# Nothing under upstream/ is edited.  The whole KaleidoPaint app is compiled
# for macOS as it stands (every Swift file except KaleidoPaintApp.swift, whose
# @main would compete with the harness's own main.swift), so the reference
# values and the drawing files come from the very code that runs on an iPhone:
# the same KaleidoPaintDocument writes and reads the files.

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SRC="$ROOT/upstream/Source - SwiftUI/KaleidoPaint"
SHARED="$ROOT/upstream/Shared/Geometry Games - Swift"
BUILD="$HERE/.build"
RESOURCES="$ROOT/geometry/src/test/resources"
OUT="$RESOURCES/reference.txt"
DRAWINGS="$RESOURCES/drawings"

mkdir -p "$BUILD" "$RESOURCES"

# The list of upstream sources, one per line (the paths contain spaces).
: > "$BUILD/sources.txt"
for f in "$SRC"/*.swift "$SHARED"/*.swift; do
	case "$f" in
		*/KaleidoPaintApp.swift) ;;
		*) printf '%s\n' "$f" >> "$BUILD/sources.txt" ;;
	esac
done
for f in "$HERE"/*.swift; do
	printf '%s\n' "$f" >> "$BUILD/sources.txt"
done

# -default-isolation MainActor and -swift-version 5 are upstream's own build
# settings (SWIFT_DEFAULT_ACTOR_ISOLATION, SWIFT_VERSION in the Xcode project).
#
# -enable-constraint-solver-performance-hacks: with Swift 6.3 the type checker
# gives up on the four-term metric expression in hitImageOfControlHandle()
# ("unable to type-check this expression in reasonable time") after a minute
# and a half.  The flag restores the older overload-pruning heuristics, under
# which the same line type-checks in under a second.  It changes how fast the
# compiler finds the types, not which types it finds.
tr '\n' '\0' < "$BUILD/sources.txt" | xargs -0 xcrun swiftc \
	-Onone \
	-swift-version 5 \
	-default-isolation MainActor \
	-Xfrontend -enable-constraint-solver-performance-hacks \
	-import-objc-header "$SRC/KaleidoPaintBridgingHeader.h" \
	-o "$BUILD/reference"

# SWIFT_DETERMINISTIC_HASHING: upstream's touch handling keeps the possible
# positions of a new stroke in a Set and takes whichever comes first.  Swift
# shuffles a Set's order from one run to the next, so the same strokes land
# one cell up or down, or left or right, depending on the run.  All of those
# are the same drawing to the eye, but not the same file; fixing the order
# makes the harness write the same files every time.
export SWIFT_DETERMINISTIC_HASHING=1

# The harness writes the drawings into a fresh directory, so a drawing that
# is no longer produced does not linger.
rm -rf "$DRAWINGS.tmp"
mkdir -p "$DRAWINGS.tmp"
"$BUILD/reference" "$DRAWINGS.tmp" "$HERE/legacy" > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
rm -rf "$DRAWINGS"
mv "$DRAWINGS.tmp" "$DRAWINGS"
echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
echo "wrote $DRAWINGS ($(ls "$DRAWINGS" | wc -l | tr -d ' ') files)"

# Drawings that did not come from the harness: the files saved by the app
# itself (geometry/src/test/resources/from-the-app, committed), and real
# drawings from elsewhere if they have been fetched
# (tools/reference/fetch-public-drawings.sh; not part of the repository, so
# neither are the reference values made from them).  Upstream reads each one
# and writes it again, beside the original.
for EXTERNAL in "$RESOURCES/from-the-app" "$ROOT/geometry/src/test/external-drawings"; do
	if ls "$EXTERNAL"/*.kaleidopaint > /dev/null 2>&1; then
		rm -f "$EXTERNAL"/*.rewritten.kaleidopaint
		"$BUILD/reference" --external "$EXTERNAL" > "$EXTERNAL/reference.txt.tmp"
		mv "$EXTERNAL/reference.txt.tmp" "$EXTERNAL/reference.txt"
		echo "wrote $EXTERNAL/reference.txt ($(wc -l < "$EXTERNAL/reference.txt" | tr -d ' ') lines)"
	fi
done
