// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.opengl.EGL14.*
import android.opengl.EGLConfig
import android.opengl.GLES31.*
import com.cinderblocksoftware.kaleidopaint.geometry.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Random

/** Pixel-by-pixel CPU oracle, including arbitrary seed colors and torus seams. */
internal object GpuFillChecks {
    fun run(): String {
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
        val context =
            eglCreateContext(
                display,
                configs[0],
                EGL_NO_CONTEXT,
                intArrayOf(EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE),
                0,
            )
        val surface =
            eglCreatePbufferSurface(
                display,
                configs[0],
                intArrayOf(EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE),
                0,
            )
        check(eglMakeCurrent(display, surface, surface, context) && GpuFloodFill.supported())
        var cases = 0
        var workLimitFallbacks = 0
        try {
            for (size in listOf(1, 2, 8, 64, 256, 2048)) {
                val texture = IntArray(1)
                glGenTextures(1, texture, 0)
                glBindTexture(GL_TEXTURE_2D, texture[0])
                glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, size, size)
                val bytes =
                    ByteBuffer.allocateDirect(size * size * 4).order(ByteOrder.nativeOrder())
                GpuFloodFill(size).use { gpu ->
                    fun test(
                        name: String,
                        pixels: IntArray,
                        seeds: IntArray,
                        color: Int,
                        allowWorkLimit: Boolean = false,
                    ) {
                        val expected = pixels.copyOf()
                        val cpu = floodFill(expected, size, seeds, color)
                        bytes.clear()
                        bytes.asIntBuffer().put(pixels)
                        glBindTexture(GL_TEXTURE_2D, texture[0])
                        glTexSubImage2D(
                            GL_TEXTURE_2D,
                            0,
                            0,
                            0,
                            size,
                            size,
                            GL_RGBA,
                            GL_UNSIGNED_BYTE,
                            bytes,
                        )
                        glMemoryBarrier(
                            GL_TEXTURE_UPDATE_BARRIER_BIT or GL_SHADER_IMAGE_ACCESS_BARRIER_BIT
                        )
                        val result =
                            try {
                                gpu.compute(texture[0], seeds, color)
                            } catch (limit: GpuFloodFill.WorkLimitException) {
                                check(allowWorkLimit) {
                                    "Unexpected limit in $name: ${limit.message}"
                                }
                                workLimitFallbacks++
                                android.util.Log.i(
                                    "GpuFillChecks",
                                    "gpu_fill_fallback $name flags=${limit.failureBits}",
                                )
                                cpu
                            }
                        val actual = pixels.copyOf()
                        val visited = BooleanArray(pixels.size)
                        for (i in result.runs.indices step 2) {
                            val start = result.runs[i]
                            val length = result.runs[i + 1]
                            check(
                                start >= 0 &&
                                    length > 0 &&
                                    start + length <= pixels.size &&
                                    start / size == (start + length - 1) / size
                            ) {
                                "Bad run $size $name"
                            }
                            for (j in start until start + length) {
                                check(!visited[j]) { "Duplicate pixel $name" }
                                visited[j] = true
                                actual[j] = color
                            }
                        }
                        check(actual.contentEquals(expected)) { "GPU pixels differ: $size $name" }
                        val expectedMask = BooleanArray(pixels.size)
                        for (i in cpu.runs.indices step 2) for (j in
                            cpu.runs[i] until cpu.runs[i] + cpu.runs[i + 1]) expectedMask[j] = true
                        check(visited.contentEquals(expectedMask)) {
                            "GPU mask differs: $size $name"
                        }
                        // The compute backend must leave source pixels untouched.
                        val fbo = IntArray(1)
                        glGenFramebuffers(1, fbo, 0)
                        glBindFramebuffer(GL_FRAMEBUFFER, fbo[0])
                        glFramebufferTexture2D(
                            GL_FRAMEBUFFER,
                            GL_COLOR_ATTACHMENT0,
                            GL_TEXTURE_2D,
                            texture[0],
                            0,
                        )
                        bytes.clear()
                        glReadPixels(0, 0, size, size, GL_RGBA, GL_UNSIGNED_BYTE, bytes)
                        val unchanged = IntArray(pixels.size)
                        bytes.asIntBuffer().get(unchanged)
                        check(unchanged.contentEquals(pixels)) { "GPU modified source: $name" }
                        glBindFramebuffer(GL_FRAMEBUFFER, 0)
                        glDeleteFramebuffers(1, fbo, 0)
                        cases++
                        android.util.Log.i(
                            "GpuFillChecks",
                            "PASS $size $name ${result.runs.size/2} runs",
                        )
                    }
                    val blank = IntArray(size * size)
                    test("full", blank, intArrayOf(0), 0xffee6611.toInt())
                    test("noop", blank, intArrayOf(0), 0)
                    test(
                        "diagonal",
                        IntArray(size * size) { if ((it % size + it / size) % 2 == 0) 0 else -1 },
                        intArrayOf(0),
                        0xff0000ff.toInt(),
                    )
                    test(
                        "wrapped-seeds",
                        IntArray(size * size) { if (it % size == size / 2) -1 else 0 },
                        intArrayOf(0, size * size - 1),
                        0xff00ff00.toInt(),
                    )
                    if (size == 2048) {
                        val serpentine =
                            IntArray(size * size) { index ->
                                val x = index % size
                                val y = index / size
                                if (y % 2 == 0 || x == if ((y / 2) % 2 == 0) size - 1 else 0) 0
                                else -1
                            }
                        repeat(6) { trial ->
                            test(
                                "whole-cell-stress-$trial",
                                blank,
                                intArrayOf(0),
                                0xff123456.toInt(),
                                true,
                            )
                            test(
                                "serpentine-stress-$trial",
                                serpentine,
                                intArrayOf(0),
                                0xff123456.toInt(),
                                true,
                            )
                        }
                        test(
                            "gpu-still-usable-after-stress",
                            blank,
                            intArrayOf(0),
                            0xff123456.toInt(),
                        )
                    }
                    if (size in 8..256) {
                        val random = Random(size.toLong())
                        repeat(20) { trial ->
                            val input = IntArray(size * size) { random.nextInt(4) * 0x11223344 }
                            val seeds =
                                IntArray(1 + trial % 12) { random.nextInt(input.size) }
                                    .distinct()
                                    .toIntArray()
                            test(
                                "random-$trial",
                                input,
                                seeds,
                                if (trial % 4 == 0) input[seeds[0]] else 0x76543210,
                            )
                        }
                    }
                }
                glDeleteTextures(1, texture, 0)
            }
            return "$cases GPU/CPU exact pixel+mask cases and untouched source; bounded-work fallbacks=$workLimitFallbacks: PASS"
        } finally {
            eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)
            eglDestroySurface(display, surface)
            eglDestroyContext(display, context)
            eglTerminate(display)
        }
    }
}
