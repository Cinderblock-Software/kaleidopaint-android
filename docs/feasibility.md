# Porting KaleidoPaint to Android — feasibility

Surveyed 2026-11-10 from `KaleidoPaint-Src.zip` as published at
https://www.geometrygames.org/KaleidoPaint/ (Last-Modified 2026-01-19),
imported unchanged into `upstream/`.

## Licence

`upstream/02 KaleidoPaint/TermsOfUse.txt`: © 2026 Jeff Weeks, GNU GPL
version 2 **or (at your option) any later version**. `GPL.txt` is GPLv2.

What that means for a port:

- Allowed: port, modify, distribute, including on Google Play, free or paid.
- Required: the port is GPL too; publish complete corresponding source; keep
  his copyright notices and the licence; mark files we changed, with dates.
- Not granted by the GPL: the *name* "KaleidoPaint" and the icon. Use them
  only with his agreement; otherwise pick another name and credit the original.
- "Or any later version" lets us release the port under GPLv3, which is
  the usual choice today (it is what most F-Droid apps use).

## What the current source is

The current app is **pure Swift + SwiftUI + Metal**. There is no C core in
it any more: the Xcode project references 30 files, all `.swift` plus one
`.metal` and two headers. The C files under `upstream/Shared/` are older
shared utilities that this app does not build.

| Part | Lines | Port effort |
|---|---|---|
| Wallpaper groups (17 groups, orbifold names, generators, the Magic Theorem notes) `KaleidoPaintWallpaperGroup.swift` | 1,451 | Direct translation; uses `simd` only |
| Curves, splines, dots, brushstrokes, coordinate systems, unit-cell placement | ~2,450 | Direct translation |
| Document model, undo/redo, file encode/decode `KaleidoPaintDocument.swift` | 3,690 | Model logic translates; SwiftUI document plumbing is rewritten |
| Main screen, toolbars, panels `KaleidoPaintContentView.swift`, help, gestures | ~4,000 | Rewrite in Jetpack Compose |
| Renderer `KaleidoPaintRenderer.swift` + shared Geometry Games renderer | ~2,500 + shared | Rewrite against OpenGL ES 3 (or Vulkan) |
| Shaders `KaleidoPaintGPUFunctions.metal` | 1,039 | Draw shaders are small; **flood fill is five GPU compute kernels** |
| Localizations (12 languages), images, help | — | Reusable as is (convert `.strings` to Android XML) |

About 16,500 app lines plus a slice of the ~19,000 shared lines.

### The hard part: fill

The paint-bucket fill runs as Metal compute kernels (`KPFloodFill*`, from
line 278 of the `.metal` file). On Android that becomes OpenGL ES 3.1
compute shaders (supported by essentially every phone still on Play's
minimum API level) or Vulkan, or a CPU flood fill as a first step. Everything
else in the renderer is triangle strips and a few control handles.

### Good news

- **Drawings are saved as UTF-8 text** (`encodeFileFormat()`), so the
  port can open and save the same files as the iPhone and Mac versions.
- The maths is cleanly separated from the UI and has no Apple dependency
  beyond `simd` vector types, which map onto small Kotlin value classes.

## The 2016 Android version

https://www.geometrygames.org/Archive/GeometryGamesForAndroid.html offers
`KaleidoPaint-2-8-1-Android.apk` for sideloading. Inspected: Java UI
(`classes.dex`) over a C core (`libKaleidoPaintJNI.so`), built for
**32-bit ARM only**, which current 64-bit-only phones cannot run. Its source
is not on the site; it is worth asking Jeff for, mainly as a reference for
the Android UI decisions, since the current Swift app has moved on from it.

## Verdict

Feasible. It is a translation plus a UI rewrite, not a recompile. The
maths ports almost line for line. The real work is the Compose interface,
the GL renderer, and the compute-shader fill. A first version that draws
in all 17 groups, names them, and saves files compatible with iOS is
the natural first milestone; fill and export come after.
