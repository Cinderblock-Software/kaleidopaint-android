// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.content.Context
import android.opengl.EGL14.*
import android.opengl.EGLConfig
import android.opengl.GLES30.*
import com.cinderblocksoftware.kaleidopaint.geometry.*
import org.json.JSONArray
import org.json.JSONObject

/** Isolated pbuffer benchmark. Does not open the UI or read/write the user's drawing. */
internal object PerformanceBenchmark {
    fun run(
        context: Context,
        stressSeconds: Int = 0,
        progress: (String) -> Unit = {},
        cancelled: () -> Boolean = { false },
        onCheckpoint: ((JSONObject) -> Unit)? = null,
    ): JSONObject {
        val display = eglGetDisplay(EGL_DEFAULT_DISPLAY)
        check(eglInitialize(display, IntArray(2), 0, IntArray(2), 1))
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        check(
            eglChooseConfig(
                display,
                intArrayOf(
                    EGL_SURFACE_TYPE,
                    EGL_PBUFFER_BIT,
                    EGL_RENDERABLE_TYPE,
                    0x0040 /* EGL_OPENGL_ES3_BIT_KHR */,
                    EGL_RED_SIZE,
                    8,
                    EGL_GREEN_SIZE,
                    8,
                    EGL_BLUE_SIZE,
                    8,
                    EGL_ALPHA_SIZE,
                    8,
                    EGL_NONE,
                ),
                0,
                configs,
                0,
                1,
                count,
                0,
            )
        )
        check(count[0] > 0)
        val glContext =
            eglCreateContext(
                display,
                configs[0],
                EGL_NO_CONTEXT,
                intArrayOf(EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE),
                0,
            )
        check(glContext != EGL_NO_CONTEXT)
        val surface =
            eglCreatePbufferSurface(
                display,
                configs[0],
                intArrayOf(EGL_WIDTH, 1080, EGL_HEIGHT, 2400, EGL_NONE),
                0,
            )
        check(surface != EGL_NO_SURFACE && eglMakeCurrent(display, surface, surface, glContext))
        val deviceBefore = DiagnosticReports.device(context)
        val report =
            JSONObject()
                .put("renderer", glGetString(GL_RENDERER))
                .put("glVersion", glGetString(GL_VERSION))
                .put("size", "1080x2400 page; 2048x2048 cell")
                .put(
                    "method",
                    "CPU wall time including glFinish; fixed synthetic scenes, offscreen, no display FPS measurement",
                )
        val version = IntArray(2)
        glGetIntegerv(GL_MAJOR_VERSION, version, 0)
        glGetIntegerv(GL_MINOR_VERSION, version, 1)
        report.put("computeSupported", version[0] > 3 || version[0] == 3 && version[1] >= 1)
        val rows = JSONArray()
        var lastLabel = ""
        fun checkpoint(label: String) {
            if (cancelled()) throw java.util.concurrent.CancellationException("Stopped")
            if (label != lastLabel) {
                lastLabel = label
                progress(label)
            }
        }
        fun scenario(
            name: String,
            doc: KaleidoPaintDocument,
            fresh: Boolean = false,
            durationSeconds: Int = 0,
            navigate: Boolean = false,
            preferGpu: Boolean = false,
        ) {
            checkpoint(name)
            onCheckpoint?.invoke(
                JSONObject(report.toString())
                    .put("state", "running")
                    .put("currentScenario", name)
                    .put("results", rows)
            )
            val caseContext =
                eglCreateContext(
                    display,
                    configs[0],
                    EGL_NO_CONTEXT,
                    intArrayOf(EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE),
                    0,
                )
            check(
                caseContext != EGL_NO_CONTEXT &&
                    eglMakeCurrent(display, surface, surface, caseContext)
            )
            try {
                val renderer = DrawingRenderer(doc, preferGpu)
                renderer.onSurfaceCreated(null, null)
                renderer.onSurfaceChanged(null, 1080, 2400)
                fun frame(): Double {
                    checkpoint(name)
                    if (navigate)
                        doc.itsUnitCellPlacement.itsCorner =
                            doc.itsUnitCellPlacement.itsCorner + Double2(.003, .002)
                    if (fresh)
                        doc.itsElements.filterIsInstance<Fill>().forEach {
                            it.itsCachedRLERunsBuffer = null
                        }
                    glFinish()
                    val start = System.nanoTime()
                    renderer.onDrawFrame(null)
                    glFinish()
                    return (System.nanoTime() - start) / 1e6
                }
                repeat(3) { frame() }
                val measured = mutableListOf<Double>()
                if (durationSeconds > 0) {
                    val until = System.nanoTime() + durationSeconds * 1_000_000_000L
                    while (System.nanoTime() < until) measured.add(frame())
                } else repeat(if (fresh) 7 else 25) { measured.add(frame()) }
                val times = measured.sorted()
                rows.put(
                    JSONObject()
                        .put("scenario", name)
                        .put("samples", times.size)
                        .put("medianMs", times[times.size / 2])
                        .put("p95Ms", times[kotlin.math.ceil(.95 * times.size).toInt() - 1])
                        .put("minMs", times.first())
                        .put("maxMs", times.last())
                        .put("requestedFillBackend", if (preferGpu) "gpu" else "cpu")
                        .put("gpuFillSuccesses", renderer.gpuFillCount)
                        .put("gpuFillFallbacks", renderer.gpuFallbackCount)
                        .put("cellCompositions", renderer.cellCompositions)
                        .put("cellReuses", renderer.cellReuses)
                        .put("deviceAfter", DiagnosticReports.device(context))
                )
            } finally {
                check(eglMakeCurrent(display, surface, surface, glContext))
                eglDestroyContext(display, caseContext)
            }
        }
        try {
            scenario("empty", KaleidoPaintDocument())
            val fixture =
                context.resources.openRawResource(R.raw.performance_fixture).bufferedReader().use {
                    it.readText()
                }
            fun fixture() = KaleidoPaintDocument().apply { decodeFileFormat(fixture) }
            scenario("four-elements-cached", fixture())
            scenario("four-elements-fresh-fill", fixture(), true)
            scenario(
                "whole-cell-fresh-fill",
                KaleidoPaintDocument().apply {
                    itsElements.add(Fill(LinearDisplayP3Color(0.0, 0.3, 1.0, 1.0), Double2(.5, .5)))
                },
                true,
            )
            fun dense() =
                KaleidoPaintDocument(WallpaperGroup.wpg632).apply {
                    repeat(500) { i ->
                        itsElements.add(
                            Dot(
                                LinearDisplayP3Color(.2, .4, .8, 1.0),
                                Double2((i * 37 % 997) / 997.0, (i * 73 % 991) / 991.0),
                                .015,
                            )
                        )
                    }
                }
            scenario("500-dots-632", dense())
            scenario("500-dots-navigation", dense(), navigate = true)
            if (GpuFloodFill.supported()) {
                scenario("four-elements-fresh-fill-gpu", fixture(), true, preferGpu = true)
                scenario(
                    "whole-cell-fresh-fill-gpu",
                    KaleidoPaintDocument().apply {
                        itsElements.add(
                            Fill(LinearDisplayP3Color(0.0, 0.3, 1.0, 1.0), Double2(.5, .5))
                        )
                    },
                    true,
                    preferGpu = true,
                )
            }
            if (stressSeconds > 0) {
                val phase = (stressSeconds / 3).coerceAtLeast(1)
                scenario("sustained-dense", dense(), durationSeconds = phase, navigate = true)
                scenario(
                    "sustained-fresh-fill",
                    KaleidoPaintDocument().apply { itsElements.add(Fill()) },
                    true,
                    phase,
                    preferGpu = FillAcceleration.enabled,
                )
                scenario("sustained-cached", fixture(), durationSeconds = phase)
            }
            report
                .put("results", rows)
                .put("state", "complete")
                .put("deviceBefore", deviceBefore)
                .put("stressSeconds", stressSeconds)
                .put("createdAt", java.time.Instant.now().toString())
            return report
        } finally {
            eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)
            eglDestroySurface(display, surface)
            eglDestroyContext(display, glContext)
            eglTerminate(display)
        }
    }
}
