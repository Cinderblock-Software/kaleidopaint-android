// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint.geometry

import org.junit.Assert.*
import org.junit.Test

class MatchingAppearanceTest {
    @Test
    fun matchingColorAndWidthUseIndependentScopesAndUndoTogether() {
        val doc = KaleidoPaintDocument().apply { itsUndoManager = UndoManager() }
        val a = Dot(color = LinearDisplayP3Color(0.0, 0.0, 1.0, 1.0), thickness = .1)
        val b = Dot(color = LinearDisplayP3Color(.001, 0.0, 1.0, 1.0), thickness = .2)
        val c = Dot(color = LinearDisplayP3Color(1.0, 0.0, 0.0, 1.0), thickness = .1)
        doc.itsElements.addAll(listOf(a, b, c))
        doc.changeElementAppearance(a, LinearDisplayP3Color(0.0, 1.0, 0.0, 1.0), .3, true, true)
        assertEquals(1.0, b.itsColor.g, 0.0)
        assertEquals(.2, b.itsThickness, 0.0)
        assertEquals(1.0, c.itsColor.r, 0.0)
        assertEquals(.3, c.itsThickness, 0.0)
        doc.itsUndoManager!!.undo()
        assertEquals(.001, b.itsColor.r, 0.0)
        assertEquals(.1, c.itsThickness, 0.0)
        assertFalse(doc.itsUndoManager!!.canUndo)
    }

    @Test
    fun widthChangesInvalidateOnlySubsequentFillMasks() {
        val doc = KaleidoPaintDocument().apply { itsUndoManager = UndoManager() }
        val mask = FillMask(4, intArrayOf(0, 2))
        val before = Fill().apply { itsCachedRLERunsBuffer = mask }
        val dot = Dot(thickness = .1)
        val after = Fill().apply { itsCachedRLERunsBuffer = mask }
        doc.itsElements.addAll(listOf(before, dot, after))
        doc.changeElementAppearance(dot, dot.itsColor, .2, matchingWidth = true)
        assertSame(mask, before.itsCachedRLERunsBuffer)
        assertNull(after.itsCachedRLERunsBuffer)
    }
}
