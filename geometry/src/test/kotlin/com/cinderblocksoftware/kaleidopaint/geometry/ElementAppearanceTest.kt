// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint.geometry

import org.junit.Assert.*
import org.junit.Test

class ElementAppearanceTest {
    @Test
    fun colorAndWidthUndoTogetherAndRedoTogether() {
        val document = KaleidoPaintDocument().apply { itsUndoManager = UndoManager() }
        val dot = Dot(color = LinearDisplayP3Color(1.0, 0.0, 0.0, 1.0), thickness = .02)
        document.itsElements.add(dot)
        var blue = LinearDisplayP3Color(0.0, 0.0, 1.0, 1.0)
        document.changeElementAppearance(dot, blue, .08)
        blue =
            blue.copy(
                b = .5
            ) // Colors are immutable values; replacing the caller value cannot alter history.
        assertEquals(.5, blue.b, 0.0)
        assertEquals(1.0, dot.itsColor.b, 0.0)
        assertEquals(.08, dot.itsThickness, 0.0)
        document.itsUndoManager!!.undo()
        assertEquals(1.0, dot.itsColor.r, 0.0)
        assertEquals(.02, dot.itsThickness, 0.0)
        assertFalse(document.itsUndoManager!!.canUndo)
        document.itsUndoManager!!.redo()
        assertEquals(1.0, dot.itsColor.b, 0.0)
        assertEquals(.08, dot.itsThickness, 0.0)
    }

    @Test
    fun recoloringFillPreservesItsEstablishedRegion() {
        val document = KaleidoPaintDocument().apply { itsUndoManager = UndoManager() }
        val fill = Fill()
        val mask = FillMask(4, intArrayOf(0, 2))
        fill.itsCachedRLERunsBuffer = mask
        document.itsElements.add(fill)
        document.changeElementAppearance(fill, LinearDisplayP3Color(0.0, 1.0, 0.0, 1.0))
        assertSame(mask, fill.itsCachedRLERunsBuffer)
        document.itsUndoManager!!.undo()
        assertSame(mask, fill.itsCachedRLERunsBuffer)
    }

    @Test
    fun unchangedAppearanceDoesNotAddUndoStep() {
        val document = KaleidoPaintDocument().apply { itsUndoManager = UndoManager() }
        val dot = Dot(thickness = .03)
        document.changeElementAppearance(dot, dot.itsColor, .03)
        assertFalse(document.itsUndoManager!!.canUndo)
    }
}
