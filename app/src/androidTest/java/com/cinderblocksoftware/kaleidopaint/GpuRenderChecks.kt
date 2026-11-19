// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.app.Instrumentation
import android.opengl.EGL14.*
import android.opengl.EGLConfig
import android.opengl.GLES30.*
import com.cinderblocksoftware.kaleidopaint.geometry.*
import java.nio.ByteBuffer

/** Real drawing pipeline, fresh and cached pixels and undo, with forced GPU success. */
internal object GpuRenderChecks {
    fun run(test: Instrumentation): String {
        val display = eglGetDisplay(EGL_DEFAULT_DISPLAY)
        check(eglInitialize(display, IntArray(2), 0, IntArray(2), 1))
        val config = arrayOfNulls<EGLConfig>(1)
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
                config,
                0,
                1,
                IntArray(1),
                0,
            )
        )
        val surface =
            eglCreatePbufferSurface(
                display,
                config[0],
                intArrayOf(EGL_WIDTH, 256, EGL_HEIGHT, 256, EGL_NONE),
                0,
            )
        val fixture =
            test.targetContext.resources
                .openRawResource(R.raw.performance_fixture)
                .bufferedReader()
                .use { it.readText() }
        fun drawing(group: WallpaperGroup, variant: Int) =
            KaleidoPaintDocument(group).apply {
                val source = KaleidoPaintDocument().apply { decodeFileFormat(fixture) }
                itsElements = source.itsElements
                itsUndoManager = UndoManager()
                itsBackgroundColor = LinearDisplayP3Color(.9, .9, .9, 1.0)
                itsColorBySymmetryFlag = variant == 1
                if (variant == 2)
                    itsElements.filterIsInstance<Fill>().forEach {
                        it.itsColor = LinearDisplayP3Color(.2, .3, .7, .5)
                    }
            }
        fun render(group: WallpaperGroup, variant: Int, gpu: Boolean): List<ByteArray> {
            val context =
                eglCreateContext(
                    display,
                    config[0],
                    EGL_NO_CONTEXT,
                    intArrayOf(EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE),
                    0,
                )
            check(eglMakeCurrent(display, surface, surface, context))
            try {
                val document = drawing(group, variant)
                val renderer = DrawingRenderer(document, gpu)
                renderer.onSurfaceCreated(null, null)
                renderer.onSurfaceChanged(null, 256, 256)
                fun frame(): ByteArray {
                    renderer.onDrawFrame(null)
                    val data = ByteBuffer.allocateDirect(256 * 256 * 4)
                    glReadPixels(0, 0, 256, 256, GL_RGBA, GL_UNSIGNED_BYTE, data)
                    check(glGetError() == GL_NO_ERROR)
                    return ByteArray(data.capacity()).also {
                        data.rewind()
                        data.get(it)
                    }
                }
                val fresh = frame()
                val cached = frame()
                check(fresh.contentEquals(cached)) { "Fresh/cache mismatch $group/$variant/$gpu" }
                val fill = document.itsElements.filterIsInstance<Fill>().first()
                document.changeElementAppearance(
                    fill,
                    LinearDisplayP3Color(.8, .1, .1, 1.0),
                    null,
                    false,
                    false,
                )
                val recolored = frame()
                document.itsUndoManager!!.undo()
                val undone = frame()
                check(undone.contentEquals(fresh)) { "Color undo mismatch $group/$variant/$gpu" }
                if (group == WallpaperGroup.wpgO && variant == 0) {
                    document.itsTouchMode = TouchMode.edit
                    frame()
                    val compositions = renderer.cellCompositions
                    val originalPlacement = document.itsUnitCellPlacement.copy()
                    document.itsUnitCellPlacement.itsCorner += Double2(.1, .2)
                    frame()
                    check(renderer.cellCompositions == compositions) { "Edit pan recomposed cell" }
                    document.itsUnitCellPlacement.itsTranslations =
                        document.itsUnitCellPlacement.itsTranslations * 8.0
                    frame()
                    check(renderer.cellCompositions > compositions) {
                        "Fill handle zoom did not recompose cell"
                    }
                    document.itsUnitCellPlacement = originalPlacement
                    document.itsTouchMode = TouchMode.draw
                }
                val exported = renderer.exportPng(size = 256, transparent = true)
                if (gpu)
                    check(renderer.gpuFillCount > 0 && renderer.gpuFallbackCount == 0) {
                        "GPU backend silently fell back $group/$variant"
                    }
                return listOf(fresh, recolored, undone, exported)
            } finally {
                eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)
                eglDestroyContext(display, context)
            }
        }
        try {
            for (group in WallpaperGroup.entries) for (variant in 0..2) {
                val cpu = render(group, variant, false)
                val gpu = render(group, variant, true)
                check(cpu.indices.all { cpu[it].contentEquals(gpu[it]) }) {
                    "CPU/GPU drawing or PNG differs: $group/$variant"
                }
                android.util.Log.i("GpuRenderChecks", "PASS ${group.orbifoldName} variant $variant")
            }
            return "17 groups x normal/symmetry/alpha: exact CPU/GPU fresh/cached/recolor/undo/export: PASS"
        } finally {
            eglDestroySurface(display, surface)
            eglTerminate(display)
        }
    }
}
