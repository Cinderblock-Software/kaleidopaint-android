// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import java.nio.ByteBuffer

/** Immutable GL readback handed to the image worker for conversion/compression. */
internal class PixelReadback(
    val imageWidth: Int,
    val imageHeight: Int,
    private val bytes: ByteBuffer,
) {
    fun pngBytes(): ByteArray {
        return run {
            val bitmap =
                android.graphics.Bitmap.createBitmap(
                    imageWidth,
                    imageHeight,
                    android.graphics.Bitmap.Config.ARGB_8888,
                )
            try {
                // Bitmap.setPixels accepts straight ARGB. Unpremultiply sampled
                // edges before passing them in; otherwise alpha is applied twice.
                // One row avoids another full-size IntArray for 4096px images.
                val row = IntArray(imageWidth)
                for (y in 0 until imageHeight) {
                    for (x in 0 until imageWidth) {
                        val offset = 4 * (y * imageWidth + x)
                        val alpha = bytes.get(offset + 3).toInt() and 255
                        fun channel(i: Int): Int {
                            val c = bytes.get(offset + i).toInt() and 255
                            return if (alpha == 0) 0
                            else if (alpha == 255) c
                            else ((c * 255 + alpha / 2) / alpha).coerceAtMost(255)
                        }
                        row[x] =
                            (alpha shl 24) or
                                (channel(0) shl 16) or
                                (channel(1) shl 8) or
                                channel(2)
                    }
                    // GLES rows run bottom-to-top; PNG rows run top-to-bottom.
                    bitmap.setPixels(row, 0, imageWidth, 0, imageHeight - 1 - y, imageWidth, 1)
                }
                java.io.ByteArrayOutputStream().use { output ->
                    check(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output))
                    output.toByteArray()
                }
            } finally {
                bitmap.recycle()
            }
        }
    }
}
