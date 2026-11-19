// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import com.cinderblocksoftware.kaleidopaint.geometry.*
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real GLES readback: run on an emulator with the comparison fixture. */
internal object ExportChecks {
    fun run(test: Instrumentation) {
        val activity =
            test.startActivitySync(
                Intent(test.targetContext, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        test.waitForIdleSync()
        fun find(view: View): CanvasView? =
            if (view is CanvasView) view
            else
                (view as? ViewGroup)?.let { group ->
                    (0 until group.childCount).firstNotNullOfOrNull { find(group.getChildAt(it)) }
                }
        var canvas: CanvasView? = null
        repeat(100) {
            test.runOnMainSync { canvas = find(activity.window.decorView) }
            if (canvas == null) Thread.sleep(50)
        }
        val surface = checkNotNull(canvas)
        val source = File(test.targetContext.filesDir, "current.kaleidopaint")
        val before = source.readText()
        fun image(size: Int, transparent: Boolean = false, tile: Boolean = false): Bitmap {
            val latch = CountDownLatch(1)
            var result: Result<ByteArray>? = null
            test.runOnMainSync {
                surface.exportPng(tile, size, transparent) {
                    result = it
                    latch.countDown()
                }
            }
            check(latch.await(60, TimeUnit.SECONDS)) { "Export timed out" }
            val bytes = checkNotNull(result).getOrThrow()
            File(test.targetContext.filesDir, "check-export-$size-$transparent-$tile.png")
                .writeBytes(bytes)
            return checkNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
        }
        fun alphaCounts(bitmap: Bitmap): Pair<Int, Int> {
            var zero = 0
            var opaque = 0
            for (y in 0 until bitmap.height step 4) for (x in 0 until bitmap.width step 4) when (
                Color.alpha(bitmap.getPixel(x, y))
            ) {
                0 -> zero++
                255 -> opaque++
            }
            return zero to opaque
        }
        val first = image(256, true)
        val second = image(256, true)
        check(first.sameAs(second)) { "Repeated cached fill export differs" }
        val (clear, ink) = alphaCounts(first)
        check(clear > 100 && ink > 100) {
            "Transparent export missing background alpha or ink: $clear/$ink"
        }
        second.recycle()
        val opaque = image(512)
        check(opaque.width == 512 && opaque.height == 512)
        check(alphaCounts(opaque).first == 0 && Color.alpha(opaque.getPixel(0, 0)) == 255) {
            "Opaque background lost"
        }
        val orange = opaque.getPixel(265, 247)
        check(
            Color.red(orange) > 240 && Color.green(orange) in 50..120 && Color.blue(orange) < 20
        ) {
            "Export flipped vertically or included edit handle"
        }
        opaque.recycle()
        val large = image(4096, true)
        check(large.width == 4096 && large.height == 4096) { "Large export cropped to surface" }
        large.recycle()
        val expected =
            KaleidoPaintDocument()
                .apply { decodeFileFormat(before) }
                .prepareModelToExportTileableRectangle(1024, 1024)
        val tile = image(1024, true, true)
        check(tile.width == expected.first && tile.height == expected.second) {
            "Rectangle dimensions wrong"
        }
        tile.recycle()
        val after = image(256, true)
        check(after.sameAs(first)) { "Rectangle export changed later page projection" }
        after.recycle()
        first.recycle()
        check(source.readText() == before) { "Preview/export changed saved drawing" }
        // A final redraw/export proves the original framebuffer and projection were restored.
        val final = image(512)
        check(final.width == 512 && final.height == 512)
        final.recycle()
    }
}
