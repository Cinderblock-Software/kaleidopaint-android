// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.app.Instrumentation
import android.content.Intent
import androidx.lifecycle.ViewModelProvider
import com.cinderblocksoftware.kaleidopaint.geometry.*
import java.io.File

internal object SessionChecks {
    fun run(test: Instrumentation): String {
        val savedFile = File(test.targetContext.filesDir, "current.kaleidopaint")
        val original =
            if (savedFile.exists()) savedFile.readBytes()
            else KaleidoPaintDocument().encodeFileFormat().toByteArray()
        val activity =
            test.startActivitySync(
                Intent(test.targetContext, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ) as MainActivity
        lateinit var session: EditorSession
        test.runOnMainSync { session = ViewModelProvider(activity)[EditorSession::class.java] }
        val document =
            KaleidoPaintDocument(WallpaperGroup.wpgO).apply { itsUndoManager = UndoManager() }
        val dot = Dot(thickness = .02)
        document.itsElements.add(dot)
        test.runOnMainSync {
            session.replace(document)
            synchronized(document) {
                document.changeElementAppearance(dot, LinearDisplayP3Color(.1, .2, .8, 1.0), .08)
                document.itsTouchMode = TouchMode.edit
                document.itsControlHandleHit =
                    ControlHandleHit(dot, null, Double2.zero, Double2.zero, Double3x3.identity, 0.0)
            }
            session.requestSave()
        }
        val monitor = test.addMonitor(MainActivity::class.java.name, null, false)
        test.runOnMainSync { activity.recreate() }
        val recreated =
            test.waitForMonitorWithTimeout(monitor, 10000) as? MainActivity
                ?: error("Recreation timed out")
        test.removeMonitor(monitor)
        test.runOnMainSync {
            val retained = ViewModelProvider(recreated)[EditorSession::class.java]
            check(retained === session && retained.document === document) {
                "Session/model replaced"
            }
            check(
                document.itsControlHandleHit?.itsElement === dot &&
                    document.itsUndoManager!!.canUndo
            ) {
                "Selection/undo lost"
            }
            document.itsUndoManager!!.undo()
            check(dot.itsThickness == .02)
            document.itsUndoManager!!.redo()
            check(dot.itsThickness == .08)
            repeat(25) { i ->
                session.replace(KaleidoPaintDocument().apply { itsBrushThickness = .02 + i * .001 })
            }
            session.requestSave(immediate = true)
        }
        val expected = session.document.encodeFileFormat()
        val path = File(test.targetContext.filesDir, "current.kaleidopaint")
        val deadline = System.nanoTime() + 10_000_000_000L
        while (
            (!path.exists() || path.readText() != expected) && System.nanoTime() < deadline
        ) Thread.sleep(30)
        check(path.readText() == expected) { "Stale queued autosave overwrote latest document" }
        Thread.sleep(400)
        check(path.readText() == expected)
        test.runOnMainSync {
            session.replace(
                KaleidoPaintDocument().apply {
                    decodeFileFormat(original.toString(Charsets.UTF_8))
                    itsUndoManager = UndoManager()
                }
            )
        }
        val restoreDeadline = System.nanoTime() + 5_000_000_000L
        while (
            path.readText() != session.document.encodeFileFormat() &&
                System.nanoTime() < restoreDeadline
        ) Thread.sleep(30)
        check(path.readText() == session.document.encodeFileFormat()) {
            "Original drawing restoration did not finish"
        }
        return "Retained model, selection, undo/redo and latest-generation background autosave: PASS"
    }
}
