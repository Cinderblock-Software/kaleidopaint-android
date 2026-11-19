// Ported from KaleidoPaintCurve.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

@file:Suppress("LocalVariableName")

package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.max

class Curve(
    color: LinearDisplayP3Color = LinearDisplayP3Color(r = 1.0, g = 0.0, b = 1.0, a = 1.0),
    thickness: Double = 0.01,
) : Brushstroke(color = color, thickness = thickness) {

    //	Cubic spline in [0,1] unit cell coordinates.
    //	Specifies a single curve, which will get transformed
    //	under the action of the torus group.
    var itsSpline: CubicSpline = CubicSpline() // 	initially empty

    companion object {
        const val maxArcSegmentCount = 64
        const val maxArcVertexCount = 2 * (maxArcSegmentCount + 1)
        val maxPointVertexCount = gUnitCircleVertexCount // 	might use only half-disk
        val triStripBufferVertexCount = max(maxArcVertexCount, maxPointVertexCount)
    }

    override fun render(
        renderEncoder: BrushstrokeRenderEncoder,
        metricOfDet1: Double2x2,
        scratchBuffer: VertexScratchBuffer, // 	guaranteed to be big enough
        symmetryCount: Int,
    ) {

        //	For conciseness
        val theNodes = itsSpline.itsNodes

        //	We shouldn't ever get a 0- or 1-element Curve,
        //	but if we did, the following code would
        //	simply draw nothing (and not crash!).
        assert( //	ignored in released app
            theNodes.size >= 2
        ) {
            "Internal error:  attempting to render a curve with 0 or 1 vertex"
        }

        //	For each node except the last one...
        for (theNode in theNodes) {
            if (theNode === theNodes.last()) {
                continue
            } //	no arc begins at the last node

            //	...draw an arc connecting the node to the next one.
            renderArc(
                fromNode = theNode,
                renderEncoder = renderEncoder,
                metricOfDet1 = metricOfDet1,
                scratchBuffer = scratchBuffer,
                symmetryCount = symmetryCount,
            )

            //	At the first node and each corner node...
            if (theNode === theNodes.first() || theNode.itsNodeType == SplineNodeType.corner) {

                //	...draw an initial half-dot.
                renderInitialHalfDot(
                    atNode = theNode,
                    renderEncoder = renderEncoder,
                    metricOfDet1 = metricOfDet1,
                    scratchBuffer = scratchBuffer,
                    symmetryCount = symmetryCount,
                )
            }
        }

        //	Draw a final half-dot at the end.
        if (theNodes.size >= 2) {

            renderFinalHalfDot(
                penultimateNode = theNodes[theNodes.size - 2],
                ultimateNode = theNodes[theNodes.size - 1],
                renderEncoder = renderEncoder,
                metricOfDet1 = metricOfDet1,
                scratchBuffer = scratchBuffer,
                symmetryCount = symmetryCount,
            )
        }
    }

    // MARK: -
    // MARK: Triangle strips

    private fun renderArc(
        fromNode: SplineNode,
        renderEncoder: BrushstrokeRenderEncoder,
        metricOfDet1: Double2x2,
        scratchBuffer: VertexScratchBuffer, // 	guaranteed to be big enough
        symmetryCount: Int,
    ) {
        val startNode = fromNode

        //	Draw a triangle strip representing the given spline arc,
        //	using the SplineNode's parameterization
        //
        //		S(u) = ξ₀(1-u) + ξ₁u + ξ₂(1-u)³ + ξ₃u³
        //
        //	where the ξ are constants and u runs from 0 to 1.
        //
        //	Adjust the triangle strip's (varying!) thickness
        //	in unit cell coordinates to give the desired
        //	constant thickness in "unit-area parallelogram" coordinates.

        //	For conciseness.
        val ξ: Double4x2 = startNode.ξ

        //	Choose a set of u-values {u₀=0.0, u₁, u₂, … , uₙ=1.0}
        //	appropriate to the arc's bending.
        //	The u-values will typically not be evenly spaced,
        //	but instead will be denser where the arc curves more sharply,
        //	and less dense where the arc curves more gently.
        //	To find such a set of u-values, we start with a set
        //	of (maxArcSegmentCount + 1) evenly spaced candidate u-values,
        //	compute the direction of the arc's tangent vector at each one,
        //	and then select a subset such that between any two consecutive u-values,
        //	the arc's direction changes by at most 2° (the maximum acceptable
        //	bending angle).

        val theCosMaxAcceptableBendingAngle = 0.99939082701909573001 // 	= cos( (π/180) * 2° )

        //	Pre-compute theUnitTangents for all candidate u-values.
        //	Normalizing the tangent vectors to unit length -- relative
        //	to the drawing-coordinates metric -- makes it easy
        //	to evaluate how the arc is bending.
        //
        val theUnitTangents =
            (0..Curve.maxArcSegmentCount).map {
                unitLengthVector(
                    v =
                        tangentVector(
                            u = it.toDouble() / Curve.maxArcSegmentCount.toDouble(),
                            ξ = ξ,
                        ),
                    metricOfDet1 = metricOfDet1,
                )
            }

        //	Consider each u-value in turn and generate triangle-strip vertics
        //	for a subset such that between any two consecutive u-values,
        //	the arc's direction changes by at most about 2° (the maximum
        //	acceptable bending angle) relative to the drawing-coordinates metric.

        var theVertexCount = 0
        var thePreviousAcceptedUnitTangent = Double2.zero

        for (i in 0..Curve.maxArcSegmentCount) {

            //	Compare unit tangent vectors to decide whether
            //	to generate triangle-strip vertics for this u-value.
            val theAcceptFlag: Boolean
            if (i == 0) {

                //	This is the first u-value, so accept it for sure.
                theAcceptFlag = true

                //	Remember the unit tangent vector here
                //	so we can compare it with later values.
                thePreviousAcceptedUnitTangent = theUnitTangents[0]
            } else if (i == Curve.maxArcSegmentCount) {

                //	This is the last u-value, so accept it for sure.
                theAcceptFlag = true

                //	Just to be tidy, clear thePreviousAcceptedUnitTangent.
                thePreviousAcceptedUnitTangent = Double2.zero
            } else { //	1 ≤ i ≤ Curve.maxArcSegmentCount - 1

                //	Accept this u-value iff its tangent vector differs
                //	by at least 2° from the most recently accepted tangent vector.
                //
                //		Note:  Strictly speaking, to keep the angle difference
                //		under 2° we'd need to accept the last u-value for which
                //		the difference is less, rather than the first u-value
                //		for which it's more.  But in practice the angle varies
                //		slowly enough that accepting the first u-value
                //		whose tangent vector differs by more than 2° is
                //		plenty good enough.  That 2° cutoff value is a bit
                //		arbitrary in any case.
                //

                //	Compute the inner product of Prev = thePreviousAcceptedUnitTangent
                //	and T = theUnitTangents[i+1] relative to the metric m
                //
                //		( Prev₀ Prev₁ )( m₀₀ m₀₁ )( T₀ )
                //		               ( m₁₀ m₁₁ )( T₁ )
                //

                val theInnerProduct =
                    (thePreviousAcceptedUnitTangent[0] *
                        metricOfDet1[0][0] *
                        theUnitTangents[i][0] +
                        thePreviousAcceptedUnitTangent[0] *
                            metricOfDet1[0][1] *
                            theUnitTangents[i][1] +
                        thePreviousAcceptedUnitTangent[1] *
                            metricOfDet1[1][0] *
                            theUnitTangents[i][0] +
                        thePreviousAcceptedUnitTangent[1] *
                            metricOfDet1[1][1] *
                            theUnitTangents[i][1])

                //	The tangent vectors have unit length, so
                //
                //		<Prev, T> = |Prev| |T| cos θ
                //		          = cos θ
                //
                //	The bending angle is too big iff its cosine is too small.
                //
                if (theInnerProduct < theCosMaxAcceptableBendingAngle) {

                    //	The bending angle between thePreviousAcceptedUnitTangent
                    //	and theUnitTangents[i] exceeds 2°.  So let's accept
                    //	the current u-value, and let the code below add
                    //	a pair of vertices to the scratchBuffer.
                    theAcceptFlag = true

                    //	The tangent vector for the current u-value
                    //	becomes the new "previous accepted unit tangent".
                    thePreviousAcceptedUnitTangent = theUnitTangents[i]
                } else {
                    //	Skip the current u-value and continue on to the next one.
                    theAcceptFlag = false

                    //	Leave thePreviousAcceptedUnitTangent as it is.
                }
            }

            if (theAcceptFlag) {

                //	Note the current u-value.
                val u = i.toDouble() / Curve.maxArcSegmentCount.toDouble()
                val uu = 1.0 - u

                //	First find the point on the curve's centerline for this value of u,
                //	ignoring the curve's thickness.  Recall that the spline
                //	is parameterized by
                //
                //		S(u) = ξ₀(1-u) + ξ₁u + ξ₂(1-u)³ + ξ₃u³
                //
                //	where the ξ are constants and u runs from 0 to 1.
                //
                val theCenterline: Double2 =
                    (uu * ξ[0] + u * ξ[1] + uu * uu * uu * ξ[2] + u * u * u * ξ[3])

                //	To account for the curve's thickness,
                //	we'll need a unit-length normal vector.
                val theUnitNormal =
                    orthogonalVector(
                        to = theUnitTangents[i],
                        metricOfDet1 = metricOfDet1,
                    )

                //	Offset alternate vertices to either side of the centerline,
                //	by the Curve's half-thickness times theNormal
                //	(keeping in mind that theNormal has unit length
                //	in the metric of the unit-area parallelogram).

                val theTriStripVertex0 = theCenterline - 0.5 * itsThickness * theUnitNormal
                val theTriStripVertex1 = theCenterline + 0.5 * itsThickness * theUnitNormal

                scratchBuffer[theVertexCount + 0] = Float2(theTriStripVertex0)
                scratchBuffer[theVertexCount + 1] = Float2(theTriStripVertex1)

                theVertexCount += 2
            }
        }

        //	Render the triangle strip vertices.

        renderEncoder.drawTriangleStrip(
            vertices = scratchBuffer,
            vertexCount = theVertexCount,
            instanceCount = symmetryCount,
        )
    }

    private fun renderInitialHalfDot(
        atNode: SplineNode,
        renderEncoder: BrushstrokeRenderEncoder,
        metricOfDet1: Double2x2,
        scratchBuffer: VertexScratchBuffer, // 	guaranteed to be big enough
        symmetryCount: Int,
    ) {
        val node = atNode

        //	For conciseness.
        val ξ: Double4x2 = node.ξ

        //	Compute a unit tangent vector at the beginning of the arc,
        //	using the formula
        //
        //		∂S
        //		-- = -ξ₀ + ξ₁ - 3ξ₂(1 - u)² + 3ξ₃u²
        //		∂u
        //
        //		   = -ξ₀ + ξ₁ - 3ξ₂(1 - 0)² + 3ξ₃0²
        //
        //		   = -ξ₀ + ξ₁ - 3ξ₂
        //
        //	Orient the half-dot in the direction opposite the direction of the arc itself.
        //
        val theTangent: Double2 = ξ[0] - ξ[1] + 3.0 * ξ[2]
        val theUnitTangent =
            unitLengthVector(
                v = theTangent,
                metricOfDet1 = metricOfDet1,
            )

        //	Let theUnitNormal be orthogonal to theUnitTangent.
        val theUnitNormal =
            orthogonalVector(
                to = theUnitTangent,
                metricOfDet1 = metricOfDet1,
            )

        renderHalfDot(
            center = node.itsNodeLocation,
            unitTangent = theUnitTangent,
            unitNormal = theUnitNormal,
            renderEncoder = renderEncoder,
            scratchBuffer = scratchBuffer,
            symmetryCount = symmetryCount,
        )
    }

    private fun renderFinalHalfDot(
        penultimateNode: SplineNode,
        ultimateNode: SplineNode,
        renderEncoder: BrushstrokeRenderEncoder,
        metricOfDet1: Double2x2,
        scratchBuffer: VertexScratchBuffer, // 	guaranteed to be big enough
        symmetryCount: Int,
    ) {

        //	For conciseness.
        val ξ: Double4x2 = penultimateNode.ξ

        //	Compute a unit tangent vector at the end of the arc,
        //	using the formula
        //
        //		∂S
        //		-- = -ξ₀ + ξ₁ - 3ξ₂(1 - u)² + 3ξ₃u²
        //		∂u
        //
        //		   = -ξ₀ + ξ₁ - 3ξ₂(1 - 1)² + 3ξ₃1²
        //
        //		   = -ξ₀ + ξ₁ + 3ξ₃
        //
        //	Orient the half-dot in the same direction as the arc itself.
        //
        val theTangent: Double2 = -ξ[0] + ξ[1] + 3.0 * ξ[3]
        val theUnitTangent =
            unitLengthVector(
                v = theTangent,
                metricOfDet1 = metricOfDet1,
            )

        //	Let theUnitNormal be orthogonal to theUnitTangent.
        val theUnitNormal =
            orthogonalVector(
                to = theUnitTangent,
                metricOfDet1 = metricOfDet1,
            )

        renderHalfDot(
            center = ultimateNode.itsNodeLocation,
            unitTangent = theUnitTangent,
            unitNormal = theUnitNormal,
            renderEncoder = renderEncoder,
            scratchBuffer = scratchBuffer,
            symmetryCount = symmetryCount,
        )
    }

    private fun renderHalfDot(
        center: Double2,
        unitTangent: Double2,
        unitNormal: Double2,
        renderEncoder: BrushstrokeRenderEncoder,
        scratchBuffer: VertexScratchBuffer, // 	guaranteed to be big enough
        symmetryCount: Int,
    ) {

        for (i in 0 until gUnitHalfCircleVertexCount) {

            val theTriStripVertex =
                (center +
                    0.5 * itsThickness * gUnitCircleVertices[i][0] * unitTangent +
                    0.5 * itsThickness * gUnitCircleVertices[i][1] * unitNormal)

            //	Convert to SIMD2<Float32> for the GPU.
            scratchBuffer[i] = Float2(theTriStripVertex)
        }

        renderEncoder.drawTriangleStrip(
            vertices = scratchBuffer,
            vertexCount = gUnitHalfCircleVertexCount,
            instanceCount = symmetryCount,
        )
    }

    // MARK: -
    // MARK: Control handle

    fun renderControlHandles(
        selectedNode: SplineNode?, // 	= nil if no node is selected
        renderEncoder: BrushstrokeRenderEncoder,
        symmetryCount: Int,
    ) {

        for (theNode in itsSpline.itsNodes) {

            val thePlacement =
                ControlHandlePlacement(
                    itsCenter = Float2(theNode.itsNodeLocation),
                    itsRadius = (0.5 * itsThickness).toFloat(),
                )
            //	multiplication by 0.5 converts diameter to radius

            val theDarkColor =
                (if (theNode.itsNodeType == SplineNodeType.smooth) Float4(0.5f, 0.5f, 0.5f, 1.0f)
                else Float4(0.0f, 0.0f, 0.0f, 1.0f))
            val theLightColor = Float4(1.0f, 1.0f, 1.0f, 1.0f)
            val theColors =
                (if (theNode === selectedNode)
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
    }

    override fun hitControlHandle(
        touchPointInExtendedUnitCellCoordinates: Double2,
        wallpaperGroup: WallpaperGroup,
        metricOfDet1: Double2x2,
        fillMarkerRadius: Double, // 	used only for Fills
    ): ControlHandleHit? {

        //	Test each SplineNode for a control-handle hit.
        //	If several nodes sit close to each other,
        //	select the node closest to the tap point.
        var thePossibleHitControlHandle: ControlHandleHit? = null
        var theTapError = Double.POSITIVE_INFINITY

        for (theNode in itsSpline.itsNodes) {

            val theHitControlHandle =
                hitImageOfControlHandle(
                    touchPointInExtendedUnitCellCoordinates =
                        touchPointInExtendedUnitCellCoordinates,
                    controlHandleCenter = theNode.itsNodeLocation,
                    controlHandleMeanRadius = 0.5 * itsThickness,
                    splineNode = theNode,
                    wallpaperGroup = wallpaperGroup,
                    metricOfDet1 = metricOfDet1,
                )
            if (theHitControlHandle != null) {

                if (theHitControlHandle.itsTapError < theTapError) {

                    thePossibleHitControlHandle = theHitControlHandle
                    theTapError = theHitControlHandle.itsTapError
                }
            }
        }

        return thePossibleHitControlHandle
    }

    // MARK: -
    // MARK: Vector computations

    private fun tangentVector(
        u: Double, // 	∈ [0.0, 1.0]
        ξ: Double4x2, // 	spline parameters
    ): Double2 {

        val uu = 1.0 - u

        //	Compute a raw tangent vector T
        //	using the derivative of the formula S(u)
        //	given at the top of renderArc().
        //
        //		∂S
        //		-- = -ξ₀ + ξ₁ - 3ξ₂(1-u)² + 3ξ₃u²
        //		∂u
        //
        val theTangent: Double2 =
            (-ξ[0] + ξ[1] - 3.0 * uu * uu * ξ[2] // 	Keep the scalar factors together, otherwise
            + 3.0 * u * u * ξ[3] // 		the Swift compiler "can't type-check
            //		the expression in a reasonable time".
            )

        return theTangent
    }
}
