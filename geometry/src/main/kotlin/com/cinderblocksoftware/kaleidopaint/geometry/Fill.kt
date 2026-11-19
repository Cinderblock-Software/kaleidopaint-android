// Ported from KaleidoPaintFill.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

// The Android renderer computes fresh fills with FloodFill.kt and replays
// cached FillMask runs. File data and control handles follow upstream.

class Fill(
    color: LinearDisplayP3Color = LinearDisplayP3Color(r = 1.0, g = 0.0, b = 1.0, a = 1.0),
    fillPoint: Double2 = Double2.zero,
) : DrawingElement(color = color) {

    //	Fill point in [0,1] unit cell coordinates.
    //	Specifies a single point, which will get transformed
    //	under the action of the torus group.
    var itsFillPoint: Double2 = fillPoint

    //	Port note:  In the original this is the Metal buffer that caches
    //	the result of the flood fill.  The document sets it to null
    //	to tell the renderer that the fill must be computed again.
    //	The Android cache is a platform-independent run mask.
    var itsCachedRLERunsBuffer: FillMask? = null

    // MARK: -
    // MARK: Control handle

    fun renderControlHandle(
        isSelected: Boolean,
        renderEncoder: BrushstrokeRenderEncoder,
        symmetryCount: Int,
        markerRadius: Double,
    ) {

        val thePlacement =
            ControlHandlePlacement(
                itsCenter = Float2(itsFillPoint),
                itsRadius = markerRadius.toFloat(),
            )

        val theDarkColor = Float4(0.0f, 0.0f, 0.0f, 1.0f)
        val theLightColor = Float4(1.0f, 1.0f, 1.0f, 1.0f)
        val theColors =
            (if (isSelected)
                ControlHandleColors( //	when node is selected
                    itsInnerColor = theDarkColor,
                    itsOuterColor = theLightColor,
                )
            else
                ControlHandleColors( //	when node is not selected
                    itsInnerColor = theLightColor,
                    itsOuterColor = theDarkColor,
                ))

        renderEncoder.drawControlHandle(
            placement = thePlacement,
            colors = theColors,
            vertexCount = gControlHandleVertexCount,
            instanceCount = symmetryCount,
        )
    }

    override fun hitControlHandle(
        touchPointInExtendedUnitCellCoordinates: Double2,
        wallpaperGroup: WallpaperGroup,
        metricOfDet1: Double2x2,
        fillMarkerRadius: Double,
    ): ControlHandleHit? {
        return hitImageOfControlHandle(
            touchPointInExtendedUnitCellCoordinates = touchPointInExtendedUnitCellCoordinates,
            controlHandleCenter = itsFillPoint,
            controlHandleMeanRadius = fillMarkerRadius,
            splineNode = null,
            wallpaperGroup = wallpaperGroup,
            metricOfDet1 = metricOfDet1,
        )
    }
}
