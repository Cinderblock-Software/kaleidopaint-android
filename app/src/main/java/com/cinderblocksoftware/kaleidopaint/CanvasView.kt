// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint

import android.content.Context
import android.opengl.GLSurfaceView
import android.view.MotionEvent
import android.view.ViewConfiguration
import com.cinderblocksoftware.kaleidopaint.geometry.DisplayPoint
import com.cinderblocksoftware.kaleidopaint.geometry.KaleidoPaintDocument
import com.cinderblocksoftware.kaleidopaint.geometry.TouchMode
import com.cinderblocksoftware.kaleidopaint.geometry.navigateWithTwoFingers
import kotlin.math.hypot

/** Android owns gesture recognition; the original document owns stroke creation. */
class CanvasView(
    context: Context,
    private val document: KaleidoPaintDocument,
    private val onCommitted: () -> Unit,
    private val onChanged: () -> Unit,
) : GLSurfaceView(context) {
    companion object {
        private val imageWorker = java.util.concurrent.Executors.newSingleThreadExecutor()
    }

    private val recovery = RenderRecovery()
    private var downX = 0f
    private var downY = 0f
    private var drawing = false
    private var cancelled = false
    private var previousPair: Pair<DisplayPoint, DisplayPoint>? = null
    private var navigated = false

    private fun pair(event: MotionEvent, skip: Int = -1): Pair<DisplayPoint, DisplayPoint>? {
        val indices = (0 until event.pointerCount).filter { it != skip }
        if (indices.size != 2) return null
        return point(event.getX(indices[0]), event.getY(indices[0])) to
            point(event.getX(indices[1]), event.getY(indices[1]))
    }

    private fun finishNavigation() {
        if (navigated) {
            document.itsUnitCellPlacement.snapToViewAlignment()
            document.itsUnitCellPlacement.centerTheUnitCell()
            document.changeCount++
        }
        navigated = false
        previousPair = null
    }

    private val slop = ViewConfiguration.get(context).scaledTouchSlop

    private var doubleTapping = false
    private val taps =
        android.view.GestureDetector(
            context,
            object : android.view.GestureDetector.SimpleOnGestureListener() {
                override fun onDown(event: MotionEvent) = true

                override fun onSingleTapConfirmed(event: MotionEvent): Boolean {
                    if (document.itsContentIsLocked || document.itsTouchMode != TouchMode.draw)
                        return false
                    synchronized(document) {
                        document.singleTapForDrawing(point(event.x, event.y))
                    }
                    requestRender()
                    onChanged()
                    onCommitted()
                    return true
                }

                override fun onDoubleTap(event: MotionEvent): Boolean {
                    doubleTapping = true
                    return true
                }

                override fun onDoubleTapEvent(event: MotionEvent): Boolean {
                    if (
                        event.actionMasked == MotionEvent.ACTION_UP &&
                            !cancelled &&
                            !navigated &&
                            !document.itsContentIsLocked &&
                            document.itsTouchMode == TouchMode.draw
                    ) {
                        synchronized(document) {
                            document.doubleTapForDrawing(point(event.x, event.y))
                        }
                        requestRender()
                        onChanged()
                        onCommitted()
                    }
                    return true
                }
            },
        )

    private fun cancelTaps() {
        val now = android.os.SystemClock.uptimeMillis()
        val cancel = MotionEvent.obtain(now, now, MotionEvent.ACTION_CANCEL, 0f, 0f, 0)
        taps.onTouchEvent(cancel)
        cancel.recycle()
        doubleTapping = false
    }

    override fun onPause() {
        cancelTaps()
        super.onPause()
    }

    override fun onDetachedFromWindow() {
        cancelTaps()
        super.onDetachedFromWindow()
    }

    var onSurfaceReady: (() -> Unit)? = null
    private val drawingRenderer = DrawingRenderer(document)

    init {
        drawingRenderer.onRenderFailure = {
            post {
                if (recovery.requestRetry()) {
                    onPause()
                    onResume()
                    requestRender()
                } else {
                    android.widget.Toast.makeText(
                            context,
                            R.string.render_failed,
                            android.widget.Toast.LENGTH_LONG,
                        )
                        .show()
                    onSurfaceReady?.invoke()
                }
            }
        }
        setEGLContextClientVersion(3)
        setRenderer(
            object : GLSurfaceView.Renderer {
                private var readyPosted = false

                override fun onSurfaceCreated(
                    gl: javax.microedition.khronos.opengles.GL10?,
                    config: javax.microedition.khronos.egl.EGLConfig?,
                ) {
                    readyPosted = false
                    try {
                        drawingRenderer.onSurfaceCreated(gl, config)
                    } catch (failure: Exception) {
                        drawingRenderer.reportFailure(failure)
                    }
                }

                override fun onSurfaceChanged(
                    gl: javax.microedition.khronos.opengles.GL10?,
                    width: Int,
                    height: Int,
                ) {
                    drawingRenderer.onSurfaceChanged(gl, width, height)
                }

                override fun onDrawFrame(gl: javax.microedition.khronos.opengles.GL10?) {
                    drawingRenderer.onDrawFrame(gl)
                    if (!readyPosted && !drawingRenderer.renderFailed) {
                        readyPosted = true
                        // Introduce Compose overlays after the SurfaceView's first
                        // frame, avoiding a startup race between the two layers.
                        postOnAnimation {
                            recovery.healthyFrame()
                            onSurfaceReady?.invoke()
                        }
                    }
                }
            }
        )
        renderMode = RENDERMODE_WHEN_DIRTY
        contentDescription = context.getString(R.string.drawing_canvas)
    }

    // DisplayPoint's origin is at the bottom left; Android's is at the top left.
    private fun point(x: Float, y: Float) =
        DisplayPoint(
            x.toDouble(),
            height - y.toDouble(),
            width.toDouble(),
            height.toDouble(),
        )

    override fun onTouchEvent(source: MotionEvent): Boolean {
        // AndroidView can transiently supply a shifted local-coordinate matrix
        // during Compose layout. Derive the view offset from screen coordinates
        // for the whole event, including historical samples and other pointers.
        val location = IntArray(2).also { getLocationOnScreen(it) }
        val event = MotionEvent.obtain(source)
        event.offsetLocation(
            source.rawX - source.x - location[0],
            source.rawY - source.y - location[1],
        )
        return try {
            handleTouch(event)
        } finally {
            event.recycle()
        }
    }

    private fun handleTouch(event: MotionEvent): Boolean {
        if (width == 0 || height == 0) return true
        if (document.itsTouchMode == TouchMode.draw && !document.itsContentIsLocked)
            taps.onTouchEvent(event)
        synchronized(document) {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    parent.requestDisallowInterceptTouchEvent(true)
                    downX = event.x
                    downY = event.y
                    drawing = false
                    cancelled = false
                    previousPair = null
                    navigated = false
                }
                MotionEvent.ACTION_POINTER_DOWN -> {
                    if (drawing) document.touchCancelled()
                    drawing = false
                    cancelled = true
                    previousPair = pair(event)
                }
                MotionEvent.ACTION_POINTER_UP -> {
                    finishNavigation()
                    previousPair = pair(event, event.actionIndex)
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (drawing) document.touchCancelled()
                    drawing = false
                    cancelled = true
                    finishNavigation()
                }
                MotionEvent.ACTION_MOVE ->
                    if (event.pointerCount == 2) {
                        val current = pair(event)
                        val previous = previousPair
                        if (current != null && previous != null) {
                            document.itsUnitCellPlacement =
                                navigateWithTwoFingers(
                                    document.itsUnitCellPlacement,
                                    previous.first,
                                    previous.second,
                                    current.first,
                                    current.second,
                                )
                            document.changeCount++
                            navigated = true
                        }
                        previousPair = current
                    } else if (!cancelled && event.pointerCount == 1) {
                        if (
                            !drawing &&
                                !doubleTapping &&
                                hypot(event.x - downX, event.y - downY) > slop
                        ) {
                            document.touchBegan(point(downX, downY))
                            drawing = true
                        }
                        if (drawing) {
                            for (i in 0 until event.historySize) {
                                document.touchMoved(
                                    point(event.getHistoricalX(i), event.getHistoricalY(i))
                                )
                            }
                            document.touchMoved(point(event.x, event.y))
                        }
                    }
                MotionEvent.ACTION_UP -> {
                    if (!cancelled) {
                        if (drawing) {
                            document.touchMoved(point(event.x, event.y))
                            document.touchEnded()
                        } else {
                            // In Draw mode, dots wait for single-tap confirmation, so a
                            // double-tap creates one fill without leaving a dot.
                            if (document.itsTouchMode != TouchMode.draw)
                                document.singleTapForEditing(point(event.x, event.y))
                            performClick()
                        }
                    }
                    drawing = false
                    finishNavigation()
                    parent.requestDisallowInterceptTouchEvent(false)
                }
            }
        }
        requestRender()
        if (
            event.actionMasked == MotionEvent.ACTION_UP ||
                event.actionMasked == MotionEvent.ACTION_CANCEL
        ) {
            doubleTapping = false
            onChanged()
            onCommitted()
        }
        return true
    }

    var previewShape: Boolean
        get() = drawingRenderer.previewShape
        set(value) {
            if (drawingRenderer.previewShape != value) {
                drawingRenderer.previewShape = value
                requestRender()
            }
        }

    val maximumExportDimension: Int
        get() = drawingRenderer.maximumExportDimension

    fun exportPng(
        tile: Boolean = false,
        size: Int? = null,
        transparent: Boolean = false,
        onResult: (Result<ByteArray>) -> Unit,
    ) {
        queueEvent {
            val pixels = runCatching { drawingRenderer.exportPixels(tile, size, transparent) }
            imageWorker.execute {
                val result =
                    pixels.fold(
                        onSuccess = { runCatching { it.pngBytes() } },
                        onFailure = { Result.failure(it) },
                    )
                android.os.Handler(android.os.Looper.getMainLooper()).post { onResult(result) }
            }
        }
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }
}
