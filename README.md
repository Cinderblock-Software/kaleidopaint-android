# KaleidoPaint for Android

An Android port of [KaleidoPaint](https://www.geometrygames.org/KaleidoPaint/)
by Jeff Weeks. Draw pictures with the symmetry of the 17 wallpaper groups, each
named in Conway's orbifold notation.

This port is made by Cinderblock Software with Jeff Weeks's permission; see
[docs/permission.md](docs/permission.md). It has not yet been released on Google Play.

## Building

Requires JDK 17 and the Android SDK (API 36).

    ./gradlew assembleDebug      # app/build/outputs/apk/debug/app-debug.apk
    ./gradlew :geometry:test     # the geometry and file-format tests

The app needs Android 8.0 (API 26) or later and OpenGL ES 3.0.

## Layout

- `app/` — the Android app: Jetpack Compose interface and OpenGL ES renderer.
- `geometry/` — the mathematics and drawing model, translated from the original
  Swift. It keeps the original's names and comments so the two can be compared.
- `upstream/` — the original KaleidoPaint source, unmodified.
- `tools/reference/` — a harness that compiles the original Swift and records the
  reference values the Kotlin tests compare against.
- `tools/port/`, `tools/localization/` — scripts that translate tables, artwork and
  strings from `upstream/`.
- `docs/feasibility.md` — the survey of the original that the port started from.

## Licence

KaleidoPaint is © Jeff Weeks and free software under the GNU General Public
License, version 2 or later; see `upstream/TermsOfUse.txt` and `upstream/GPL.txt`.
This port is free software under the GNU General Public License, version 3 or
later; see [LICENSE](LICENSE).

The GPL does not cover the name or the icon. They are used here, as "KaleidoPaint
for Android", with the original author's permission.
