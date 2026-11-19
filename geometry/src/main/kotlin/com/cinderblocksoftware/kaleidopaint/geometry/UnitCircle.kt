// Ported from KaleidoPaintRenderer.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.cos
import kotlin.math.sin

//	Port note:  Only the vertex tables at the top of KaleidoPaintRenderer.swift
//	are here, because Dot and Curve need them.  The renderer itself
//	belongs to the app module.

//	Approximate the unit circle as a regular polygon,
//	rendered as a triangle strip.
val gUnitCircleVertices: List<Double2> = run {

    //	theVertexCount ≡ 2 (mod 4) so that a half-dot may
    //	include the vertices at (0,+1) and (0,-1), while placing
    //	all vertex pairs symmetrically across the x-axis.
    val theVertexCount = 22
    val theVertexPairCount = theVertexCount / 2
    val theAngleIncrement = 2.0 * Math.PI / theVertexCount.toDouble()

    val theVertices = MutableList(theVertexCount) { Double2.zero }

    //	List the unit circle's vertices in an order suitable
    //	for rendering a dot as a triangle strip.
    for (i in 0 until theVertexPairCount) {

        val theAngle = (0.5 + i.toDouble()) * theAngleIncrement
        val theCosine = cos(theAngle)
        val theSine = sin(theAngle)

        theVertices[2 * i + 0] = Double2(theCosine, +theSine)
        theVertices[2 * i + 1] = Double2(theCosine, -theSine)
    }

    theVertices
}
val gUnitCircleVertexCount = gUnitCircleVertices.size

//	The half-circle is the "eastern" half of the unit circle.
val gUnitHalfCircleVertexCount = gUnitCircleVertexCount / 2 + 1

val gRawControlHandleVertices: List<Double2> =
    listOf(
        Double2(-1.0, -1.0),
        Double2(+1.0, -1.0),
        Double2(-1.0, +1.0),
        Double2(+1.0, +1.0),
    )
val gControlHandleVertexCount = gRawControlHandleVertices.size
