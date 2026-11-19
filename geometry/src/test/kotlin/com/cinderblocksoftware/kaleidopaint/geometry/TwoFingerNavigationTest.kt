// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.sqrt
import org.junit.Assert.*
import org.junit.Test

class TwoFingerNavigationTest {
    private fun point(x: Double, y: Double) = DisplayPoint(x, y, 1000.0, 1000.0)

    private fun assertPoint(expected: Double2, actual: Double2) {
        assertEquals(expected.x, actual.x, 1e-12)
        assertEquals(expected.y, actual.y, 1e-12)
    }

    @Test
    fun translationPreservesCellShape() {
        val initial = UnitCellPlacement(WallpaperGroup.wpgO)
        val moved =
            navigateWithTwoFingers(
                initial,
                point(200.0, 400.0),
                point(600.0, 400.0),
                point(300.0, 500.0),
                point(700.0, 500.0),
            )
        val delta = 0.1 / sqrt(2.0)
        assertPoint(initial.itsCorner + Double2(delta, delta), moved.itsCorner)
        assertPoint(initial.itsTranslations[0], moved.itsTranslations[0])
        assertPoint(initial.itsTranslations[1], moved.itsTranslations[1])
    }

    @Test
    fun combinedQuarterTurnAndZoomAroundViewCenter() {
        val initial = UnitCellPlacement(WallpaperGroup.wpgO)
        val moved =
            navigateWithTwoFingers(
                initial,
                point(400.0, 500.0),
                point(600.0, 500.0),
                point(500.0, 300.0),
                point(500.0, 700.0),
            )
        val original = initial.itsTranslations[0]
        assertPoint(Double2(-2 * original.y, 2 * original.x), moved.itsTranslations[0])
        assertFalse(moved.unitCellIsDegenerate())
    }

    @Test
    fun collapsedAndCoincidentTouchesCannotMakeCellSingular() {
        val initial = UnitCellPlacement(WallpaperGroup.wpg632)
        val collapsed =
            navigateWithTwoFingers(
                initial,
                point(400.0, 500.0),
                point(600.0, 500.0),
                point(500.0, 500.0),
                point(500.0, 500.0),
            )
        assertPoint(initial.itsTranslations[0], collapsed.itsTranslations[0])
        val coincident =
            navigateWithTwoFingers(
                initial,
                point(500.0, 500.0),
                point(500.0, 500.0),
                point(400.0, 500.0),
                point(600.0, 500.0),
            )
        assertPoint(initial.itsTranslations[0], coincident.itsTranslations[0])
    }
}
