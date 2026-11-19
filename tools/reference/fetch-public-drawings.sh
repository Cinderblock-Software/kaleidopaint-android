#!/bin/sh
# Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
#
# Fetches the real KaleidoPaint drawings that are publicly downloadable, for
# the optional ExternalDrawingsTest:
#
#     tools/reference/fetch-public-drawings.sh
#     tools/reference/build.sh
#     ./gradlew :geometry:test
#
# They are the source files of two paintings in the KaleidoPaint Users' Image
# Gallery (https://www.geometrygames.org/KaleidoPaint/Gallery/), found in the
# gallery's Images directory.  The gallery says submitted paintings are made
# available under the Creative Commons Attribution-ShareAlike 3.0 Unported
# License, citing the artist.  That licence is not the GPL, so the drawings are
# fetched here rather than committed: geometry/src/test/external-drawings/ is
# ignored by git.
#
# The site's robots.txt asks for ten seconds between requests.

set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/geometry/src/test/external-drawings"
BASE="https://www.geometrygames.org/KaleidoPaint/Gallery/Images"

mkdir -p "$OUT"

FIRST=1
for NAME in "Dave Henderson" "Mara Zanner"; do
	if [ -f "$OUT/$NAME.kaleidopaint" ]; then
		echo "have  $NAME.kaleidopaint"
		continue
	fi
	if [ "$FIRST" -eq 0 ]; then
		sleep 10
	fi
	FIRST=0
	URL="$BASE/$(printf '%s' "$NAME" | sed 's/ /%20/g').kaleidopaint"
	curl --fail --silent --show-error --output "$OUT/$NAME.kaleidopaint" "$URL"
	echo "fetched $NAME.kaleidopaint"
done
