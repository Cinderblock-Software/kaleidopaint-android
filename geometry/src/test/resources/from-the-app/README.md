# Files written by KaleidoPaint itself

Saved by KaleidoPaint 3.1.2, built from `upstream/` without changes and run
on an iOS simulator (2026-11-11). They are what the real app writes, as
opposed to what the reference harness makes upstream's document class write.

- `new-drawing.kaleidopaint` — the file the app writes when "Create
  Document" is tapped. It differs from `drawings/empty.kaleidopaint` in one
  respect: the running app registers 632 as the group new drawings start in
  (`KaleidoPaintApp.swift`), while the harness does not run that file, so its
  empty drawing is in the fallback group ○.
- `three-strokes-and-a-fill.kaleidopaint` — the same drawing after three
  strokes were drawn on the simulator's screen and a region was filled with a
  double tap, saved by leaving the drawing. The strokes were ours, made for
  this test.

`*.rewritten.kaleidopaint` and `reference.txt` are made by
`tools/reference/build.sh`: what upstream's document class reads from each
file and writes after reading it. `ExternalDrawingsTest` compares the Kotlin
port with them.

How the files were made: copy `upstream/` aside (the Xcode project expects
`Shared/` two levels above `Source - SwiftUI/`, so link it there), build the
`KaleidoPaint` scheme for a simulator with `CODE_SIGNING_ALLOWED=NO`,
install and launch it with `simctl`, drive it with Appium's XCUITest driver
(`appium:isHeadless`), and copy the drawing out of the app's
`Documents` folder (`simctl get_app_container … data`). Xcode needs its Metal
toolchain component (`xcodebuild -downloadComponent MetalToolchain`).
