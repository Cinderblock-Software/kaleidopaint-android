// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint.geometry

import java.util.BitSet
import kotlin.math.floor

/** Cached horizontal runs, as (row-major start, length) pairs. No run crosses a row. */
data class FillMask(val size: Int, val runs: IntArray)

/** Bottom-up GLES seed coordinates; unlike Metal, no vertical flip is needed. */
fun fillSeeds(point: Double2, group: WallpaperGroup, size: Int): IntArray {
    require(size > 0 && size and (size - 1) == 0)
    val mask = size - 1
    return group.torusGroup.itsElements
        .map { symmetry ->
            val p = symmetry.itsMatrix * Double3(point, 1.0)
            val x = floor(p.x * size).toInt() and mask
            val y = floor(p.y * size).toInt() and mask
            y * size + x
        }
        .distinct()
        .toIntArray()
}

/**
 * CPU equivalent of upstream's flood-fill semantics, not its parallel GPU queue. Exact target-color
 * equality, toroidal wrapping, eight-way connectivity at production resolution, all symmetry seeds,
 * and normalization of seed colors follow KaleidoPaintFill.swift and
 * KPFloodFillSetUpQueueComputeFunction. Pixels are changed on enqueue, bounding the queue to one
 * entry per pixel.
 */
fun floodFill(
    pixels: IntArray,
    size: Int,
    seeds: IntArray,
    color: Int,
    eightWay: Boolean = true,
): FillMask {
    require(size in 1..4096 && size and (size - 1) == 0 && pixels.size == size * size)
    require(seeds.all { it in pixels.indices })
    if (seeds.isEmpty()) return FillMask(size, IntArray(0))
    val target = pixels[seeds[0]]
    if (target == color) return FillMask(size, IntArray(0))
    // Upstream normalizes every symmetrical seed to the first seed's target,
    // even when rounding near a boundary put it in a differently colored pixel.
    for (seed in seeds) pixels[seed] = target
    val visited = BitSet(pixels.size)
    val queue = IntArray(pixels.size)
    var head = 0
    var tail = 0
    fun enqueue(index: Int) {
        if (pixels[index] == target) {
            pixels[index] = color
            visited.set(index)
            queue[tail++] = index
        }
    }
    for (seed in seeds) enqueue(seed)
    val wrap = size - 1
    val rowOffsets = intArrayOf(-1, 1)
    while (head < tail) {
        val index = queue[head++]
        val x = index and wrap
        val y = index / size
        enqueue(y * size + ((x - 1) and wrap))
        enqueue(y * size + ((x + 1) and wrap))
        for (dy in rowOffsets) {
            val row = ((y + dy) and wrap) * size
            enqueue(row + x)
            if (eightWay) {
                enqueue(row + ((x - 1) and wrap))
                enqueue(row + ((x + 1) and wrap))
            }
        }
    }
    // Store only filled pixels, not all pre-existing pixels of the fill color.
    var runs = IntArray(4096)
    var used = 0
    fun appendRun(start: Int, length: Int) {
        if (used + 2 > runs.size) runs = runs.copyOf(runs.size * 2)
        runs[used++] = start
        runs[used++] = length
    }
    var start = visited.nextSetBit(0)
    while (start >= 0) {
        val end = visited.nextClearBit(start)
        var part = start
        while (part < end) {
            val stop = minOf(end, (part / size + 1) * size)
            appendRun(part, stop - part)
            part = stop
        }
        start = visited.nextSetBit(end)
    }
    return FillMask(size, if (used == runs.size) runs else runs.copyOf(used))
}
