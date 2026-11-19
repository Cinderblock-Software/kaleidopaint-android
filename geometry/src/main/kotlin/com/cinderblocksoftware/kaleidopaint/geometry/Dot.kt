// Ported from KaleidoPaintDot.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

class Dot(
    color: LinearDisplayP3Color = LinearDisplayP3Color(r = 1.0, g = 0.0, b = 1.0, a = 1.0),
    center: Double2 = Double2.zero,
    thickness: Double = 0.01,
) : Brushstroke(color = color, thickness = thickness) {

    //	The Dot's center in [0,1] unit cell coordinates.
    //	Specifies a single point, which will get transformed
    //	under the action of the torus group.
    var itsCenter: Double2 = center

    companion object {
        val triStripBufferVertexCount = gUnitCircleVertexCount
    }

    override fun render(
        renderEncoder: BrushstrokeRenderEncoder,
        metricOfDet1: Double2x2,
        scratchBuffer: VertexScratchBuffer, // 	guaranteed to be big enough
        symmetryCount: Int,
    ) {

        //	Choose a pair of vectors that will
        //	be orthonormal in drawing coordinates.
        val theBasisVectorA =
            unitLengthVector(
                v = Double2(1.0, 0.0), // 	arbitrary non-zero vector
                metricOfDet1 = metricOfDet1,
            )
        val theBasisVectorB =
            orthogonalVector(
                to = theBasisVectorA,
                metricOfDet1 = metricOfDet1,
            )

        for (i in 0 until gUnitCircleVertexCount) {

            val theTriStripVertex =
                (itsCenter +
                    0.5 * itsThickness * gUnitCircleVertices[i][0] * theBasisVectorA +
                    0.5 * itsThickness * gUnitCircleVertices[i][1] * theBasisVectorB)

            //	Convert to SIMD2<Float32> for the GPU.
            scratchBuffer[i] = Float2(theTriStripVertex)
        }

        renderEncoder.drawTriangleStrip(
            vertices = scratchBuffer,
            vertexCount = gUnitCircleVertexCount,
            instanceCount = symmetryCount,
        )
    }

    // MARK: -
    // MARK: Control handle

    fun renderControlHandle(
        isSelected: Boolean,
        renderEncoder: BrushstrokeRenderEncoder,
        symmetryCount: Int,
    ) {
        //	The diameter of the control point should be less than
        //	the diameter of the dot itself, so that the dot remains visible.
        val theScaleFactor = 0.5
        val thePlacement =
            ControlHandlePlacement(
                itsCenter = Float2(itsCenter),
                itsRadius = (theScaleFactor * 0.5 * itsThickness).toFloat(),
            )
        //	multiplication by 0.5 converts diameter to radius

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
        fillMarkerRadius: Double, // 	used only for Fills
    ): ControlHandleHit? {
        return hitImageOfControlHandle(
            touchPointInExtendedUnitCellCoordinates = touchPointInExtendedUnitCellCoordinates,
            controlHandleCenter = itsCenter,
            controlHandleMeanRadius = 0.5 * itsThickness,
            splineNode = null,
            wallpaperGroup = wallpaperGroup,
            metricOfDet1 = metricOfDet1,
        )
    }
}
