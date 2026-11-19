// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint.geometry

import org.junit.Assert.*
import org.junit.Test

class FloodFillTest {
    private fun count(mask: FillMask) = mask.runs.indices.step(2).sumOf { mask.runs[it + 1] }

    @Test
    fun wrappingJoinsOppositeEdgesWithoutCrossingBarrier() {
        val p = IntArray(16) { 9 }
        p[4] = 0
        p[7] = 0
        p[5] = 0 // row 1, positions 0,3 and 1
        val mask = floodFill(p, 4, intArrayOf(4), 3, false)
        assertEquals(3, count(mask))
        assertEquals(3, p[7])
        assertEquals(9, p[6])
    }

    @Test
    fun diagonalConnectivityIsExplicit() {
        val p = IntArray(16) { 9 }
        p[0] = 0
        p[5] = 0
        assertEquals(1, count(floodFill(p.copyOf(), 4, intArrayOf(0), 3, false)))
        assertEquals(2, count(floodFill(p.copyOf(), 4, intArrayOf(0), 3, true)))
    }

    @Test
    fun enclosedRegionStaysInsideItsBoundary() {
        val p = IntArray(64)
        for (x in 1..6) {
            p[8 + x] = 9
            p[48 + x] = 9
        }
        for (y in 1..6) {
            p[y * 8 + 1] = 9
            p[y * 8 + 6] = 9
        }
        assertEquals(16, count(floodFill(p, 8, intArrayOf(3 * 8 + 3), 4)))
        assertEquals(0, p[0])
        assertEquals(9, p[9])
    }

    @Test
    fun symmetricalSeedsNormalizeDifferentColorsAndDeduplicate() {
        val p = IntArray(16) { 9 }
        p[0] = 0
        p[10] = 7
        val result = floodFill(p, 4, intArrayOf(0, 10, 10), 3)
        assertEquals(2, count(result))
        assertEquals(3, p[10])
    }

    @Test
    fun noOpAndCachedRunsExcludeExistingFillColor() {
        val p = IntArray(16) { 3 }
        p[0] = 0
        val mask = floodFill(p, 4, intArrayOf(0), 3)
        assertEquals(1, count(mask))
        assertEquals(0, count(floodFill(p, 4, intArrayOf(0), 3)))
    }

    @Test
    fun uniformCellFillsOnceAndRunsDoNotCrossRows() {
        val p = IntArray(256)
        val mask = floodFill(p, 16, intArrayOf(0, 255), 5)
        assertEquals(256, count(mask))
        assertEquals(32, mask.runs.size)
        for (i in mask.runs.indices.step(2)) {
            assertEquals(0, mask.runs[i] % 16)
            assertEquals(16, mask.runs[i + 1])
        }
    }

    @Test
    fun fullProductionResolutionHasBoundedQueueAndCompleteRows() {
        val start = System.nanoTime()
        val mask = floodFill(IntArray(2048 * 2048), 2048, intArrayOf(0), 7)
        assertEquals(2048 * 2048, count(mask))
        assertEquals(2048 * 2, mask.runs.size)
        println("2048-square CPU fill: ${(System.nanoTime()-start)/1_000_000} ms")
    }

    @Test
    fun seedCoordinatesWrapAndUseAllGroupImages() {
        assertArrayEquals(intArrayOf(15), fillSeeds(Double2(-.1, -.1), WallpaperGroup.wpgO, 4))
        assertEquals(12, fillSeeds(Double2(.137, .293), WallpaperGroup.wpgS632, 2048).size)
        assertEquals(1, fillSeeds(Double2.zero, WallpaperGroup.wpg632, 2048).size)
    }

    @Test
    fun exactBoundarySeedsUseBottomUpGlesPixels() {
        // GLES framebuffer row zero is the bottom: no Metal top-down y flip.
        for (row in 0..4) for (column in 0..4) {
            assertArrayEquals(
                intArrayOf((row % 4) * 4 + column % 4),
                fillSeeds(Double2(column / 4.0, row / 4.0), WallpaperGroup.wpgO, 4),
            )
        }
    }
}
