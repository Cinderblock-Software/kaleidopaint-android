// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.app.Instrumentation
import java.io.File

internal object ReviewChecks {
    fun run(test: Instrumentation): String {
        val directory =
            File(test.targetContext.cacheDir, "review-library-${System.nanoTime()}").apply {
                mkdirs()
            }
        try {
            val store = DrawingStore(directory)
            val automatic = store.archive(byteArrayOf(1))
            check(store.displayName(automatic, "Dessin").startsWith("Dessin "))
            val reopened = DrawingStore(directory)
            reopened.archives()
            check(reopened.displayName(automatic, "Dessin").startsWith("Dessin "))
            val named = store.archive(byteArrayOf(2), "Drawing 2026-11-14 21-03-07")
            check(store.displayName(named, "Dessin") == "Drawing 2026-11-14 21-03-07")
            val historical =
                File(automatic.parentFile, "Drawing 2026-11-14 21-03-07 abcdef.kaleidopaint")
                    .apply { writeBytes(byteArrayOf(3)) }
            check(store.displayName(historical, "Dessin") == "Drawing 2026-11-14 21-03-07")
            store.deleteArchive(automatic)
            check(!File(automatic.path + ".auto-name").exists())
            check(
                store.archives() ==
                    listOf(historical, named).sortedByDescending { it.lastModified() }
            )
        } finally {
            directory.deleteRecursively()
        }
        val recovery = RenderRecovery()
        check(recovery.requestRetry())
        check(!recovery.requestRetry()) // repeated failure without a healthy frame cannot loop
        recovery.healthyFrame()
        check(recovery.requestRetry()) // a later unrelated episode can recover again
        return "Localized automatic names, exact explicit/historical names, metadata deletion and bounded recovery episodes: PASS"
    }
}
