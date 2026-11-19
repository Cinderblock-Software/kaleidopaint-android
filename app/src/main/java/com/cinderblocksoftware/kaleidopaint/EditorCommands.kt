// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

enum class EditorAction(val reportName: String) {
    UNDO("undo"),
    REDO("redo"),
    DRAW("draw"),
    EDIT("edit"),
    FILL("fill"),
    LOCK("lock"),
    GUIDES("guides"),
    COLORS("colors"),
    REALIGN("realign"),
    SHAPE("shape"),
    HELP("help"),
    CLEAR("clear"),
    ABOUT("about"),
}

enum class FileAction {
    NEW,
    LIBRARY,
    SNAPSHOT,
    OPEN,
    SAVE,
}

enum class ColorTarget {
    BRUSH,
    FILL,
    BACKGROUND,
}

enum class EditorDialog {
    SHAPE,
    HELP,
    CLEAR,
    SMOOTHING,
}

internal enum class ChromePanel(val colorTarget: ColorTarget? = null) {
    BRUSH(ColorTarget.BRUSH),
    FILL(ColorTarget.FILL),
    BACKGROUND(ColorTarget.BACKGROUND),
    WIDTH,
    SMOOTHING,
    SYMMETRY,
    EXPORT,
    HELP,
}
