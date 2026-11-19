// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint.geometry

import org.junit.Assert.*
import org.junit.Test

class ReviewSafetyTest {
    private val valid = KaleidoPaintDocument(WallpaperGroup.wpgO).encodeFileFormat()

    @Test
    fun unsafePlacementsAreRejectedBeforeNavigation() {
        for (placement in
            listOf(
                "0 0\n1 0\n0 -1",
                "0 0\n0 0\n0 0",
                "nan 0\n1 0\n0 1",
                "0 0\ninf 0\n0 1",
                "0 0\n1e300 0\n0 1e-300",
                "1e308 0\n0.25 0\n0 0.25",
            )) {
            val file =
                valid.replace(
                    Regex("(unit cell placement\\n)(?:[^\\n]*\\n){3}"),
                    "unit cell placement\n$placement\n",
                )
            try {
                KaleidoPaintDocument().decodeFileFormat(file)
                fail("Accepted $placement")
            } catch (expected: KaleidoPaintDocument.KaleidoPaintFileEncodingError) {}
        }
    }

    @Test
    fun futureVersionsAreRejected() {
        for (version in listOf("1.11", "2.0", "0.10", "-1.10")) {
            try {
                KaleidoPaintDocument()
                    .decodeFileFormat(valid.replace("format 1.10", "format $version"))
                fail(version)
            } catch (expected: KaleidoPaintDocument.KaleidoPaintFileEncodingError) {}
        }
    }

    @Test
    fun zoomLimitRetainsRotationAndTranslation() {
        val initial =
            UnitCellPlacement(WallpaperGroup.wpgO).apply {
                itsTranslations = Double2x2(Double2(40.0, 0.0), Double2(0.0, 40.0))
            }
        fun p(x: Double, y: Double) = DisplayPoint(x, y, 1000.0, 1000.0)
        val moved =
            navigateWithTwoFingers(
                initial,
                p(450.0, 500.0),
                p(550.0, 500.0),
                p(600.0, 350.0),
                p(600.0, 650.0),
            )
        assertEquals(40.0, moved.itsTranslations[0].y, 1e-10)
        assertEquals(0.0, moved.itsTranslations[0].x, 1e-10)
        assertNotEquals(initial.itsCorner.x, moved.itsCorner.x, 0.0)
    }

    @Test
    fun largeTileDimensionsDoNotOverflowTheDiagonal() {
        val document = KaleidoPaintDocument(WallpaperGroup.wpgO)
        document.prepareModelToExportTileableRectangle(100000, 100000)
        assertTrue(document.itsUnitCellPlacement.itsTranslations[0].x.isFinite())
        assertTrue(document.itsUnitCellPlacement.itsTranslations.determinant > 0.0)
    }

    @Test
    fun zeroPaddingKeepsSignAndDoesNotTruncate() {
        assertEquals("-0012", stringWithFormat("%05d", -12))
        assertEquals("001.25", stringWithFormat("%06.2f", 1.25))
        assertEquals("123456", stringWithFormat("%03d", 123456))
    }

    @Test
    fun foundationZeroWidthSpaceIsASeparator() {
        assertEquals(listOf("a", "b"), componentsSeparatedByWhitespacesAndNewlines("a\u200Bb"))
    }
}
