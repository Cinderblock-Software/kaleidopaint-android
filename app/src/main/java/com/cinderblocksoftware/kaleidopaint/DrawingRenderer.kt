// Ported from KaleidoPaintRenderer.swift and KaleidoPaintGPUFunctions.metal
// (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint

import android.opengl.GLES30.*
import android.opengl.GLSurfaceView
import com.cinderblocksoftware.kaleidopaint.geometry.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * The first Android draw pipeline. Like upstream, render a square unit cell, then sample it
 * repeatedly across a page whose diagonal has length one. GLES samples textures with y increasing
 * upwards, so Metal's texture y flip must NOT be copied here. All document access uses the document
 * monitor. Symmetry guides and color-by-symmetry use the upstream group data.
 */
class DrawingRenderer(
    private val sourceDocument: KaleidoPaintDocument,
    private val preferGpu: Boolean? = null,
) : GLSurfaceView.Renderer, BrushstrokeRenderEncoder {
    @Volatile
    var renderFailed = false
        private set

    var onRenderFailure: (() -> Unit)? = null
    private val uniforms = mutableMapOf<Int, MutableMap<String, Int>>()

    private fun uniform(program: Int, name: String) =
        uniforms
            .getOrPut(program) { mutableMapOf() }
            .getOrPut(name) { glGetUniformLocation(program, name) }

    private val instanceVertices = floats(FloatArray(16 * 16 * 13))
    private val pageVertices = floats(FloatArray(16))
    private val pageCorners = intArrayOf(-1, -1, -1, 1, 1, -1, 1, 1)
    private val handleVertices =
        floats(
            gRawControlHandleVertices
                .flatMap { listOf(it.x.toFloat(), it.y.toFloat()) }
                .toFloatArray()
        )
    private var document = sourceDocument
    private var snapshot: RenderSnapshot? = null
    var cellCompositions = 0
        private set

    var cellReuses = 0
        private set

    private var cellState: RenderState? = null
    private var frameSnapshot: RenderSnapshot? = null
    private var gpuFill: GpuFloodFill? = null
    private var gpuAvailable = false
    private var gpuFailed = false
    var gpuFillCount = 0
        private set

    var gpuFallbackCount = 0
        private set

    private var stripProgram = 0
    private var fillProgram = 0
    private var handleProgram = 0
    private var pageProgram = 0
    private var framebuffer = 0
    private var texture = 0
    private var stripVao = 0
    private var pageVao = 0
    private var vertexBuffer = 0
    private var instanceBuffer = 0
    private var pageBuffer = 0
    private var width = 1
    private var height = 1
    private var symmetryCount = 0
    private val scratch =
        VertexScratchBuffer(maxOf(Dot.triStripBufferVertexCount, Curve.triStripBufferVertexCount))
    private val vertexBytes =
        ByteBuffer.allocateDirect(scratch.itsFloats.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
    private val markers = mutableMapOf<WallpaperGroup, List<Curve>>()
    @Volatile var previewShape = false
    private var cellReady = false
    private var reuseCell = false
    private var exporting = false
    private var transparentExport = false
    private var destinationFramebuffer = 0
    @Volatile
    var maximumExportDimension = 2048
        private set

    private var color = 0
    private val fillVertices = floats(FloatArray(1024 * 12))

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        renderFailed = false
        uniforms.clear()
        gpuFill = null
        gpuFailed = false
        gpuAvailable = GpuFloodFill.supported()
        cellReady = false
        cellState = null
        snapshot = null
        maximumExportDimension =
            IntArray(1).also { glGetIntegerv(GL_MAX_TEXTURE_SIZE, it, 0) }[0].coerceAtMost(4096)
        stripProgram =
            program(
                """#version 300 es
            layout(location=0) in vec2 position;
            layout(location=1) in vec3 col0;
            layout(location=2) in vec3 col1;
            layout(location=3) in vec3 col2;
            layout(location=4) in vec4 instanceColor;
            out vec4 symmetryColor;
            void main() {
                symmetryColor=instanceColor;
                vec3 p = mat3(col0,col1,col2) * vec3(position,1.0);
                gl_Position = vec4(2.0*p.xy-1.0,0.0,1.0);
            }
        """,
                """#version 300 es
            precision highp float;
            uniform vec4 color;
            uniform bool useSymmetry;
            in vec4 symmetryColor;
            out vec4 result;
            void main() { vec4 c=useSymmetry ? symmetryColor : color; result=vec4(c.rgb*c.a,c.a); }
        """,
            )
        fillProgram =
            program(
                """#version 300 es
            layout(location=0) in vec2 position;
            void main() { gl_Position=vec4(position,0.0,1.0); }
        """,
                """#version 300 es
            precision highp float;
            uniform vec4 color;
            out vec4 result;
            void main() { result=vec4(color.rgb*color.a,color.a); }
        """,
            )
        handleProgram =
            program(
                """#version 300 es
            layout(location=0) in vec2 position;
            layout(location=1) in vec3 col0;
            layout(location=2) in vec3 col1;
            layout(location=3) in vec3 col2;
            uniform mat2 basis;
            uniform vec2 center;
            uniform float radius;
            out vec2 uv;
            void main() {
                vec2 translated = center + radius * basis * position;
                vec3 p = mat3(col0,col1,col2) * vec3(translated,1.0);
                gl_Position=vec4(2.0*p.xy-1.0,0.0,1.0);
                uv=position;
            }
        """,
                """#version 300 es
            precision highp float;
            uniform vec4 innerColor;
            uniform vec4 outerColor;
            in vec2 uv;
            out vec4 result;
            void main() {
                float r2=dot(uv,uv);
                const float outerFadeInnerRadiusSquared=0.81;
                const float ringOuterRadiusSquared=0.64;
                const float ringInnerRadiusSquared=0.49;
                float alpha=clamp((1.0-r2)/(1.0-outerFadeInnerRadiusSquared),0.0,1.0);
                float s=clamp((ringOuterRadiusSquared-r2)/(ringOuterRadiusSquared-ringInnerRadiusSquared),0.0,1.0);
                result=mix(outerColor,innerColor,s)*alpha;
            }
        """,
            )
        pageProgram =
            program(
                """#version 300 es
            layout(location=0) in vec2 position;
            layout(location=1) in vec2 cell;
            out vec2 uv;
            void main() { gl_Position = vec4(position,0.0,1.0); uv = cell; }
        """,
                """#version 300 es
            precision highp float;
            uniform sampler2D image;
            uniform vec4 background;
            in vec2 uv;
            out vec4 result;
            void main() {
                vec4 drawing=texture(image,uv);
                result=drawing+background*(1.0-drawing.a);
            }
        """,
            )
        color = uniform(stripProgram, "color")
        stripVao = generate { glGenVertexArrays(1, it, 0) }
        pageVao = generate { glGenVertexArrays(1, it, 0) }
        vertexBuffer = generate { glGenBuffers(1, it, 0) }
        instanceBuffer = generate { glGenBuffers(1, it, 0) }
        pageBuffer = generate { glGenBuffers(1, it, 0) }
        glBindVertexArray(stripVao)
        glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GL_FLOAT, false, 8, 0)
        glBindBuffer(GL_ARRAY_BUFFER, instanceBuffer)
        for (column in 0..2) {
            glEnableVertexAttribArray(column + 1)
            glVertexAttribPointer(column + 1, 3, GL_FLOAT, false, 52, column * 12)
            glVertexAttribDivisor(column + 1, 1)
        }
        glEnableVertexAttribArray(4)
        glVertexAttribPointer(4, 4, GL_FLOAT, false, 52, 36)
        glVertexAttribDivisor(4, 1)
        glBindVertexArray(pageVao)
        glBindBuffer(GL_ARRAY_BUFFER, pageBuffer)
        for (attribute in 0..1) {
            glEnableVertexAttribArray(attribute)
            glVertexAttribPointer(attribute, 2, GL_FLOAT, false, 16, attribute * 8)
        }
        texture = generate { glGenTextures(1, it, 0) }
        glBindTexture(GL_TEXTURE_2D, texture)
        glTexStorage2D(GL_TEXTURE_2D, 12, GL_RGBA8, CELL_SIZE, CELL_SIZE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
        val extensionCount = IntArray(1)
        glGetIntegerv(GL_NUM_EXTENSIONS, extensionCount, 0)
        if (
            (0 until extensionCount[0]).any {
                glGetStringi(GL_EXTENSIONS, it) == "GL_EXT_texture_filter_anisotropic"
            }
        ) {
            val maximum = FloatArray(1)
            glGetFloatv(0x84FF, maximum, 0)
            glTexParameterf(GL_TEXTURE_2D, 0x84FE, minOf(16f, maximum[0]))
        }
        framebuffer = generate { glGenFramebuffers(1, it, 0) }
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0)
        check(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE) {
            "Unit-cell framebuffer incomplete"
        }
        glDisable(GL_DEPTH_TEST)
        glDisable(GL_CULL_FACE)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        this.width = width
        this.height = height
    }

    override fun onDrawFrame(gl: GL10?) {
        if (exporting) {
            renderFrame()
            return
        }
        if (renderFailed) return
        try {
            snapshot = RenderSnapshot.capture(sourceDocument, snapshot)
            document = snapshot!!.model
            frameSnapshot = snapshot
            renderFrame()
            snapshot!!.publishCaches(sourceDocument)
            snapshot!!.complete()
        } catch (failure: Exception) {
            reportFailure(failure)
        }
    }

    internal fun reportFailure(failure: Exception) {
        if (BuildConfig.DEBUG) throw failure
        renderFailed = true
        cellReady = false
        cellState = null
        android.util.Log.e("KaleidoPaint", "Renderer failed: " + failure.javaClass.simpleName)
        onRenderFailure?.invoke()
    }

    private fun renderFrame() {
        val background =
            if (exporting && transparentExport) floatArrayOf(0f, 0f, 0f, 0f)
            else displayColor(document.itsBackgroundColor).also { for (i in 0..2) it[i] *= it[3] }
        if (
            !reuseCell &&
                (!previewShape || !cellReady) &&
                (!cellReady || cellState != checkNotNull(frameSnapshot).completedState)
        ) {
            cellCompositions++
            glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
            glViewport(0, 0, CELL_SIZE, CELL_SIZE)
            glClearColor(0f, 0f, 0f, 0f)
            glClear(GL_COLOR_BUFFER_BIT)
            glUseProgram(stripProgram)
            glBindVertexArray(stripVao)
            // Upstream's writeUnitCellSymmetries(): shifts -1 ... +2 in both
            // directions cover the padded safe region around the unit cell.
            val transforms = instanceVertices.apply { clear() }
            for (dx in -1..2) for (dy in -1..2) {
                for (element in document.itsWallpaperGroup.torusGroup.itsElements) {
                    for (column in 0..2) for (row in 0..2) {
                        val shift =
                            if (column != 2) 0
                            else
                                when (row) {
                                    0 -> dx
                                    1 -> dy
                                    else -> 0
                                }
                        transforms.put((element.itsMatrix[column][row] + shift).toFloat())
                    }
                    for (component in displayColor(element.itsColor)) transforms.put(component)
                }
            }
            symmetryCount = transforms.position() / 13
            glBindBuffer(GL_ARRAY_BUFFER, instanceBuffer)
            val instances = transforms.apply { flip() }
            glBufferData(GL_ARRAY_BUFFER, symmetryCount * 13 * 4, instances, GL_STREAM_DRAW)
            // Preserve element order: each fill sees only the elements before it.
            // Background is composed later, so it never changes fill topology.
            for (element in document.itsElements) when (element) {
                is Brushstroke -> drawStroke(element)
                is Fill -> drawFill(element)
            }
            document.itsCurveInProgress?.let { drawStroke(it) }
            if (document.itsShowSingularitiesFlag) {
                for (marker in
                    markers.getOrPut(document.itsWallpaperGroup) {
                        singularityMarkers(document.itsWallpaperGroup)
                    }) {
                    drawStroke(marker, false)
                }
            }
            if (document.itsTouchMode == TouchMode.edit && !exporting) {
                glUseProgram(handleProgram)
                glEnable(GL_BLEND)
                glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
                val hit = document.itsControlHandleHit
                for (element in document.itsElements) when (element) {
                    is Fill ->
                        element.renderControlHandle(
                            hit?.itsElement === element,
                            this,
                            symmetryCount,
                            document.fillMarkerRadius(),
                        )
                    is Dot ->
                        element.renderControlHandle(
                            hit?.itsElement === element,
                            this,
                            symmetryCount,
                        )
                    is Curve ->
                        element.renderControlHandles(
                            if (hit?.itsElement === element) hit.itsNode else null,
                            this,
                            symmetryCount,
                        )
                }
                glDisable(GL_BLEND)
            }
            glBindTexture(GL_TEXTURE_2D, texture)
            glGenerateMipmap(GL_TEXTURE_2D)
            checkNotNull(frameSnapshot).complete()
            cellState = checkNotNull(frameSnapshot).completedState
        } else {
            cellReuses++
        }
        cellReady = true
        glDisable(GL_BLEND)
        glBindFramebuffer(GL_FRAMEBUFFER, destinationFramebuffer)
        glViewport(0, 0, width, height)
        glUseProgram(pageProgram)
        glBindVertexArray(pageVao)
        val (w, h) = convertPageSizeToDrawingCoordinates(width.toDouble(), height.toDouble())
        val page = pageVertices.apply { clear() }
        for (i in pageCorners.indices step 2) {
            val x = pageCorners[i]
            val y = pageCorners[i + 1]
            val uv =
                convertDrawingCoordinatesToExtendedUnitCellCoordinates(
                    Double2(x * w / 2, y * h / 2),
                    document.itsUnitCellPlacement,
                )
            page.put(x.toFloat()).put(y.toFloat()).put(uv.x.toFloat()).put(uv.y.toFloat())
        }
        glBindBuffer(GL_ARRAY_BUFFER, pageBuffer)
        page.flip()
        glBufferData(GL_ARRAY_BUFFER, 16 * 4, page, GL_STREAM_DRAW)
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, texture)
        glUniform1i(uniform(pageProgram, "image"), 0)
        glUniform4fv(uniform(pageProgram, "background"), 1, background, 0)
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
        check(glGetError() == GL_NO_ERROR) { "OpenGL drawing error" }
    }

    /** Reuse the composed cell, rendering exports to an independent RGBA target. */
    fun exportPng(
        tile: Boolean = false,
        size: Int? = null,
        transparent: Boolean = false,
    ): ByteArray = exportPixels(tile, size, transparent).pngBytes()

    internal fun exportPixels(
        tile: Boolean = false,
        size: Int? = null,
        transparent: Boolean = false,
    ): PixelReadback {
        val exported = RenderSnapshot.capture(sourceDocument, snapshot, exporting = true)
        document = exported.model
        frameSnapshot = exported
        val savedWidth = width
        val savedHeight = height
        var outputTexture = 0
        var outputFramebuffer = 0
        exporting = true
        return try {
            // Like upstream, prepare the slow composed cell once; only the page
            // projection and target dimensions change for preview/export.
            renderFrame()
            if (size != null) {
                require(size in 1..maximumExportDimension) { "Unsupported export dimensions" }
                width = size
                height = size
            }
            if (tile) {
                val dimensions = document.prepareModelToExportTileableRectangle(width, height)
                width = dimensions.first
                height = dimensions.second
            }
            require(
                width > 0 &&
                    height > 0 &&
                    width <= maximumExportDimension &&
                    height <= maximumExportDimension
            )
            outputTexture = generate { glGenTextures(1, it, 0) }
            glBindTexture(GL_TEXTURE_2D, outputTexture)
            glTexImage2D(
                GL_TEXTURE_2D,
                0,
                GL_RGBA8,
                width,
                height,
                0,
                GL_RGBA,
                GL_UNSIGNED_BYTE,
                null,
            )
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
            outputFramebuffer = generate { glGenFramebuffers(1, it, 0) }
            glBindFramebuffer(GL_FRAMEBUFFER, outputFramebuffer)
            glFramebufferTexture2D(
                GL_FRAMEBUFFER,
                GL_COLOR_ATTACHMENT0,
                GL_TEXTURE_2D,
                outputTexture,
                0,
            )
            check(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE) {
                "Export framebuffer incomplete"
            }
            destinationFramebuffer = outputFramebuffer
            transparentExport = transparent
            reuseCell = true
            onDrawFrame(null)
            val bytes = ByteBuffer.allocateDirect(width * height * 4)
            glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, bytes)
            check(glGetError() == GL_NO_ERROR) { "Export readback failed" }
            PixelReadback(width, height, bytes)
        } finally {
            destinationFramebuffer = 0
            transparentExport = false
            reuseCell = false
            glBindFramebuffer(GL_FRAMEBUFFER, 0)
            if (outputFramebuffer != 0) glDeleteFramebuffers(1, intArrayOf(outputFramebuffer), 0)
            if (outputTexture != 0) glDeleteTextures(1, intArrayOf(outputTexture), 0)
            if (document.itsRestorableUnitCellPlacement != null)
                document.restoreModelAfterExportingTileableRectangle()
            width = savedWidth
            height = savedHeight
            exporting = false
            exported.publishCaches(sourceDocument)
            onDrawFrame(null)
        }
    }

    private fun drawStroke(
        stroke: Brushstroke,
        bySymmetry: Boolean = document.itsColorBySymmetryFlag,
    ) {
        glEnable(GL_BLEND)
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
        glUseProgram(stripProgram)
        glUniform1i(uniform(stripProgram, "useSymmetry"), if (bySymmetry) 1 else 0)
        glUniform4fv(color, 1, displayColor(stroke.itsColor), 0)
        stroke.render(this, document.itsUnitCellPlacement.itsMetricOfDet1, scratch, symmetryCount)
    }

    private fun drawFill(fill: Fill) {
        glDisable(GL_BLEND)
        // Use a neutral fill color when dots and curves are colored by symmetry.
        val rgba =
            displayColor(
                if (document.itsColorBySymmetryFlag)
                    LinearDisplayP3Color(224.0 / 255, 224.0 / 255, 224.0 / 255, 1.0)
                else fill.itsColor
            )
        val packed = ByteBuffer.allocate(4).order(ByteOrder.nativeOrder())
        for (i in rgba.indices) packed.put(
            (rgba[i] * (if (i < 3) rgba[3] else 1f) * 255f + .5f).toInt().toByte()
        )
        packed.rewind()
        val packedColor = packed.int
        var mask = fill.itsCachedRLERunsBuffer
        if (mask == null || mask.size != CELL_SIZE) {
            mask = null
            if ((preferGpu ?: FillAcceleration.enabled) && gpuAvailable && !gpuFailed) {
                val start = System.nanoTime()
                try {
                    val engine = gpuFill ?: GpuFloodFill(CELL_SIZE).also { gpuFill = it }
                    glBindFramebuffer(GL_FRAMEBUFFER, 0)
                    mask =
                        engine.compute(
                            texture,
                            fillSeeds(fill.itsFillPoint, document.itsWallpaperGroup, CELL_SIZE),
                            packedColor,
                        )
                    fill.itsCachedRLERunsBuffer = mask
                    gpuFillCount++
                } catch (error: Exception) {
                    val workLimit = error is GpuFloodFill.WorkLimitException
                    gpuFailed = !workLimit
                    gpuFallbackCount++
                    if (!workLimit) {
                        gpuFill?.close()
                        gpuFill = null
                        repeat(16) { glGetError() } // bounded cleanup, including a lost context
                    }
                    android.util.Log.w(
                        "KaleidoPaint",
                        "GPU fill fallback (backend disabled=$gpuFailed): " +
                            error.javaClass.simpleName,
                    )
                } finally {
                    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer)
                    glBindVertexArray(stripVao)
                }
            }
        }
        if (mask == null || mask.size != CELL_SIZE) {
            val start = System.nanoTime()
            val bytes =
                ByteBuffer.allocateDirect(CELL_SIZE * CELL_SIZE * 4).order(ByteOrder.nativeOrder())
            glReadPixels(0, 0, CELL_SIZE, CELL_SIZE, GL_RGBA, GL_UNSIGNED_BYTE, bytes)
            val readBack = System.nanoTime()
            val ints = bytes.asIntBuffer()
            val pixels = IntArray(CELL_SIZE * CELL_SIZE)
            ints.get(pixels)
            // Pack components in native byte order to match glReadPixels.
            val copied = System.nanoTime()
            val computed =
                floodFill(
                    pixels,
                    CELL_SIZE,
                    fillSeeds(fill.itsFillPoint, document.itsWallpaperGroup, CELL_SIZE),
                    packedColor,
                )
            val filled = System.nanoTime()
            fill.itsCachedRLERunsBuffer = computed
            ints.rewind()
            ints.put(pixels)
            bytes.rewind()
            glBindTexture(GL_TEXTURE_2D, texture)
            glTexSubImage2D(
                GL_TEXTURE_2D,
                0,
                0,
                0,
                CELL_SIZE,
                CELL_SIZE,
                GL_RGBA,
                GL_UNSIGNED_BYTE,
                bytes,
            )
            android.util.Log.i(
                "KaleidoPaint",
                "CPU fill ${(System.nanoTime()-start)/1_000_000} ms; ${computed.runs.size/2} runs",
            )
            if (BuildConfig.DEBUG)
                android.util.Log.d(
                    "KaleidoPerf",
                    "fill readbackAllocNs=${readBack-start} copyNs=${copied-readBack} floodNs=${filled-copied} uploadSubmitNs=${System.nanoTime()-filled}",
                )
            return
        }
        glUseProgram(fillProgram)
        glUniform4fv(uniform(fillProgram, "color"), 1, rgba, 0)
        glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
        fillVertices.clear()
        fun flush() {
            if (fillVertices.position() == 0) return
            val count = fillVertices.position() / 2
            fillVertices.flip()
            glBufferData(GL_ARRAY_BUFFER, count * 8, fillVertices, GL_STREAM_DRAW)
            glDrawArrays(GL_TRIANGLES, 0, count)
            fillVertices.clear()
        }
        for (i in mask.runs.indices.step(2)) {
            if (fillVertices.remaining() < 12) flush()
            val first = mask.runs[i]
            val length = mask.runs[i + 1]
            val x0 = 2f * (first % CELL_SIZE) / CELL_SIZE - 1f
            val x1 = 2f * ((first % CELL_SIZE) + length) / CELL_SIZE - 1f
            val y0 = 2f * (first / CELL_SIZE) / CELL_SIZE - 1f
            val y1 = 2f * ((first / CELL_SIZE) + 1) / CELL_SIZE - 1f
            fillVertices
                .put(x0)
                .put(y0)
                .put(x1)
                .put(y0)
                .put(x0)
                .put(y1)
                .put(x0)
                .put(y1)
                .put(x1)
                .put(y0)
                .put(x1)
                .put(y1)
        }
        flush()
    }

    override fun drawTriangleStrip(
        vertices: VertexScratchBuffer,
        vertexCount: Int,
        instanceCount: Int,
    ) {
        vertexBytes.clear()
        vertexBytes.put(vertices.itsFloats, 0, vertexCount * 2)
        vertexBytes.flip()
        glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
        glBufferData(GL_ARRAY_BUFFER, vertexCount * 8, vertexBytes, GL_STREAM_DRAW)
        glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, vertexCount, instanceCount)
    }

    override fun drawControlHandle(
        placement: ControlHandlePlacement,
        colors: ControlHandleColors,
        vertexCount: Int,
        instanceCount: Int,
    ) {
        // Choose a pair of vectors that will be orthonormal in drawing coordinates.
        val metric = document.itsUnitCellPlacement.itsMetricOfDet1
        val a = unitLengthVector(Double2(1.0, 0.0), metric)
        val b = orthogonalVector(a, metric)
        glUniformMatrix2fv(
            uniform(handleProgram, "basis"),
            1,
            false,
            floatArrayOf(a.x.toFloat(), a.y.toFloat(), b.x.toFloat(), b.y.toFloat()),
            0,
        )
        glUniform2f(uniform(handleProgram, "center"), placement.itsCenter.x, placement.itsCenter.y)
        glUniform1f(uniform(handleProgram, "radius"), placement.itsRadius)
        fun handleColor(name: String, c: Float4) {
            glUniform4fv(
                uniform(handleProgram, name),
                1,
                displayColor(
                    LinearDisplayP3Color(
                        c.x.toDouble(),
                        c.y.toDouble(),
                        c.z.toDouble(),
                        c.w.toDouble(),
                    )
                ),
                0,
            )
        }
        handleColor("innerColor", colors.itsInnerColor)
        handleColor("outerColor", colors.itsOuterColor)
        glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
        glBufferData(GL_ARRAY_BUFFER, handleVertices.capacity() * 4, handleVertices, GL_STREAM_DRAW)
        glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, vertexCount, instanceCount)
    }

    companion object {
        private const val CELL_SIZE = 2048

        // Keep model colors in Linear Display P3. This first GLES surface is
        // sRGB: convert primaries, then gamma encode once before storage.
        private fun displayColor(c: LinearDisplayP3Color): FloatArray {
            val rgb = gP3toSRGB * Double3(c.r, c.g, c.b)
            return floatArrayOf(
                gammaEncode(rgb.x).coerceIn(0.0, 1.0).toFloat(),
                gammaEncode(rgb.y).coerceIn(0.0, 1.0).toFloat(),
                gammaEncode(rgb.z).coerceIn(0.0, 1.0).toFloat(),
                c.a.toFloat(),
            )
        }

        private fun floats(values: FloatArray) =
            ByteBuffer.allocateDirect(values.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
                .apply {
                    put(values)
                    flip()
                }

        private fun generate(call: (IntArray) -> Unit) = IntArray(1).also(call)[0]

        private fun program(vertex: String, fragment: String): Int {
            fun shader(type: Int, source: String): Int {
                val shader = glCreateShader(type)
                glShaderSource(shader, source)
                glCompileShader(shader)
                val status = IntArray(1)
                glGetShaderiv(shader, GL_COMPILE_STATUS, status, 0)
                check(status[0] != 0) { glGetShaderInfoLog(shader) }
                return shader
            }
            val vs = shader(GL_VERTEX_SHADER, vertex)
            val fs = shader(GL_FRAGMENT_SHADER, fragment)
            val program = glCreateProgram()
            glAttachShader(program, vs)
            glAttachShader(program, fs)
            glLinkProgram(program)
            val status = IntArray(1)
            glGetProgramiv(program, GL_LINK_STATUS, status, 0)
            check(status[0] != 0) { glGetProgramInfoLog(program) }
            glDeleteShader(vs)
            glDeleteShader(fs)
            return program
        }
    }
}
