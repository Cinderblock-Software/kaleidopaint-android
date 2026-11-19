// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint.geometry

private data class AppearanceChange(
    val element: DrawingElement,
    val oldColor: LinearDisplayP3Color,
    val newColor: LinearDisplayP3Color,
    val oldWidth: Double?,
    val newWidth: Double?,
)

/** One Apply is one undo step, including optional matching-color/width edits. */
fun KaleidoPaintDocument.changeElementAppearance(
    element: DrawingElement,
    color: LinearDisplayP3Color,
    thickness: Double? = null,
    matchingColor: Boolean = false,
    matchingWidth: Boolean = false,
) {
    val original = element.itsColor.copy()
    val desired = color.copy()
    val width = (element as? Brushstroke)?.itsThickness
    val colorChanged = original != desired
    val thicknessChanged = width != null && thickness != null && width != thickness
    if (!colorChanged && !thicknessChanged) return
    val candidates =
        if (itsElements.any { it === element }) itsElements.toList() else listOf(element)
    val changes = candidates.mapNotNull { candidate ->
        val oldColor = candidate.itsColor.copy()
        val oldWidth = (candidate as? Brushstroke)?.itsThickness
        val colorTarget =
            colorChanged &&
                (candidate === element || matchingColor && oldColor.isAlmostTheSameAs(original))
        val widthTarget =
            thicknessChanged &&
                oldWidth != null &&
                (candidate === element || matchingWidth && oldWidth == width)
        val nextColor = if (colorTarget) desired.copy() else oldColor.copy()
        val nextWidth = if (widthTarget) thickness else oldWidth
        if (oldColor == nextColor && oldWidth == nextWidth) null
        else AppearanceChange(candidate, oldColor, nextColor, oldWidth, nextWidth)
    }
    if (changes.isEmpty()) return
    fun applyChanges(forward: Boolean) {
        var firstWidthChange: DrawingElement? = null
        for (change in changes) {
            val value = if (forward) change.newColor else change.oldColor
            val nextWidth = if (forward) change.newWidth else change.oldWidth
            val stroke = change.element as? Brushstroke
            if (stroke != null && nextWidth != null && stroke.itsThickness != nextWidth) {
                if (firstWidthChange == null) firstWidthChange = stroke
                stroke.itsThickness = nextWidth
            }
            change.element.itsColor = value.copy()
        }
        // Color changes preserve established fill regions, like upstream.
        // A geometry change invalidates fills from the first affected stroke.
        firstWidthChange?.let { clearCachedRLERuns(from = it) }
        changeCount++
        itsBaseDrawingTextureFullRedrawRequestCount++
        itsUndoRedoCount++
    }
    doSomethingUndoably(
        doOperation = { applyChanges(true) },
        undoOperation = { applyChanges(false) },
    )
}
