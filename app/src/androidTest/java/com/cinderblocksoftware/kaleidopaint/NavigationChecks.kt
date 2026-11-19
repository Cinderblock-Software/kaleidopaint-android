// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.app.Instrumentation
import android.content.Intent
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import com.cinderblocksoftware.kaleidopaint.geometry.*
import java.io.File
import kotlin.math.abs
import kotlin.math.sqrt

/** Native navigation checks, invoked by the general instrumentation runner. */
internal class NavigationChecks(private val test: Instrumentation) {
    private fun load() =
        KaleidoPaintDocument().apply {
            decodeFileFormat(File(test.targetContext.filesDir, "current.kaleidopaint").readText())
        }

    private fun length(v: Double2) = sqrt(v.x * v.x + v.y * v.y)

    private fun gesture(
        a0: Pair<Float, Float>,
        b0: Pair<Float, Float>,
        a1: Pair<Float, Float>,
        b1: Pair<Float, Float>,
    ) {
        val down = SystemClock.uptimeMillis()
        fun event(action: Int, points: List<Pair<Float, Float>>) {
            val properties =
                points.indices
                    .map { index ->
                        MotionEvent.PointerProperties().apply {
                            id = index
                            toolType = MotionEvent.TOOL_TYPE_FINGER
                        }
                    }
                    .toTypedArray()
            val coords =
                points
                    .map { p ->
                        MotionEvent.PointerCoords().apply {
                            x = p.first
                            y = p.second
                            pressure = 1f
                            size = .1f
                        }
                    }
                    .toTypedArray()
            val event =
                MotionEvent.obtain(
                    down,
                    SystemClock.uptimeMillis(),
                    action,
                    points.size,
                    properties,
                    coords,
                    0,
                    0,
                    1f,
                    1f,
                    0,
                    0,
                    InputDevice.SOURCE_TOUCHSCREEN,
                    0,
                )
            test.sendPointerSync(event)
            event.recycle()
        }
        event(MotionEvent.ACTION_DOWN, listOf(a0))
        event(
            MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
            listOf(a0, b0),
        )
        for (i in 1..12) {
            val t = i / 12f
            fun mix(p: Pair<Float, Float>, q: Pair<Float, Float>) =
                (p.first + (q.first - p.first) * t) to (p.second + (q.second - p.second) * t)
            event(MotionEvent.ACTION_MOVE, listOf(mix(a0, a1), mix(b0, b1)))
            SystemClock.sleep(25)
        }
        event(
            MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
            listOf(a1, b1),
        )
        event(MotionEvent.ACTION_UP, listOf(a1))
        test.waitForIdleSync()
        SystemClock.sleep(
            400
        ) // allow the 200 ms debounced autosave to commit before file assertions
    }

    fun run(): String {
        val activity =
            test.startActivitySync(
                Intent(test.targetContext, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ) as MainActivity
        test.waitForIdleSync()
        val focused = java.util.concurrent.atomic.AtomicBoolean(false)
        for (attempt in 0 until 100) {
            test.runOnMainSync { focused.set(activity.hasWindowFocus()) }
            if (focused.get()) break
            SystemClock.sleep(50)
        }
        check(focused.get()) { "Drawing activity never gained input focus" }
        test.runOnMainSync {
            androidx.lifecycle
                .ViewModelProvider(activity)[EditorSession::class.java]
                .requestSave(immediate = true)
        }
        val saved = File(test.targetContext.filesDir, "current.kaleidopaint")
        val deadline = System.nanoTime() + 5_000_000_000L
        while (!saved.exists() && System.nanoTime() < deadline) SystemClock.sleep(20)
        val before = load()
        val originalCount = before.itsElements.size
        val initial = before.itsUnitCellPlacement.copy()
        gesture(350f to 1000f, 650f to 1000f, 430f to 1100f, 730f to 1100f)
        val panned = load()
        check(panned.itsElements.size == originalCount) { "Pan created drawing elements" }
        check(
            abs(
                length(initial.itsTranslations[0]) -
                    length(panned.itsUnitCellPlacement.itsTranslations[0])
            ) < 1e-8
        )
        check(initial.itsCorner != panned.itsUnitCellPlacement.itsCorner) {
            "Pan did not move the cell"
        }
        gesture(350f to 1000f, 650f to 1000f, 275f to 1000f, 725f to 1000f)
        val zoomed = load()
        check(zoomed.itsElements.size == originalCount) { "Pinch created drawing elements" }
        val ratio =
            length(zoomed.itsUnitCellPlacement.itsTranslations[0]) /
                length(initial.itsTranslations[0])
        check(abs(ratio - 1.5) < 1e-6) { "Unexpected pinch scale: $ratio" }
        gesture(350f to 1000f, 650f to 1000f, 500f to 1150f, 500f to 850f)
        val rotated = load()
        check(rotated.itsElements.size == originalCount) { "Rotation created drawing elements" }
        val a = zoomed.itsUnitCellPlacement.itsTranslations[0]
        val b = rotated.itsUnitCellPlacement.itsTranslations[0]
        val dot = (a.x * b.x + a.y * b.y) / (length(a) * length(b))
        check(abs(dot) < 1e-6) { "Rotation was not a quarter turn: cosine=$dot" }
        return "pan, 1.5x pinch, 90-degree rotation, no stray strokes: PASS"
    }
}
