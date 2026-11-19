// Ported from GeometryGamesView.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

@file:Suppress("PropertyName")

package com.cinderblocksoftware.kaleidopaint.geometry

//	Port note:  Only the two structs below come from GeometryGamesView.swift.
//	The rest of that file is the SwiftUI view that hosts the Metal layer,
//	which the Android app replaces with its own view.

//	A DisplayPoint is convenient for reporting gesture locations
//	in a simple format.
class DisplayPoint(

    //	Measurements may be in pixels or points;
    //	either is fine just so they're consistent.

    val x: Double, // 	left-to-right, from 0 to viewWidth
    val y: Double, // 	bottom-to-top, from 0 to viewHeight
    val viewWidth: Double,
    val viewHeight: Double,
)

//	A DisplayPointMotion is just like a DisplayPoint, except that
//	it stores a relative motion instead of an absolute position.
class DisplayPointMotion(

    //	Measurements may be in pixels or points;
    //	either is fine just so they're consistent.

    val Δx: Double, // 	left-to-right motion is positive
    val Δy: Double, // 	bottom-to-top motion is positive
    val viewWidth: Double,
    val viewHeight: Double,
)
