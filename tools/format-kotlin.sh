#!/usr/bin/env bash
# Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
set -euo pipefail
cd "$(dirname "$0")/.."
version=0.64
jar="${KTFMT_JAR:-${XDG_CACHE_HOME:-$HOME/.cache}/kaleidopaint-tools/ktfmt-$version.jar}"
if [[ ! -f "$jar" ]]; then
  mkdir -p "$(dirname "$jar")"
  curl --fail --location --output "$jar.tmp" "https://repo.maven.apache.org/maven2/com/facebook/ktfmt/$version/ktfmt-$version-with-dependencies.jar"
  mv "$jar.tmp" "$jar"
fi
java="${JAVA_HOME:+$JAVA_HOME/bin/}java"
[[ -z "${JAVA_HOME:-}" && -x /opt/homebrew/opt/openjdk@17/bin/java ]] && java=/opt/homebrew/opt/openjdk@17/bin/java
if [[ "${1:-}" == --check ]]; then
  find app/src geometry/src -name '*.kt' -print0 | xargs -0 "$java" -jar "$jar" --kotlinlang-style --quiet --dry-run --set-exit-if-changed
else
  find app/src geometry/src -name '*.kt' -print0 | xargs -0 "$java" -jar "$jar" --kotlinlang-style --quiet
fi
