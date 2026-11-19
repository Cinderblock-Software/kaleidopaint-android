// Ported from KaleidoPaintGPUDefinitions.h (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

//	Port note:  Only the two control handle structs are here so far,
//	because Dot and Curve fill them in.  The rest of the header describes
//	the data shared between the renderer and its shaders,
//	and gets ported along with them.

class ControlHandlePlacement(
    val itsCenter: Float2, // 	in unit cell coordinates
    val itsRadius: Float, // 	in unit cell coordinates
)

class ControlHandleColors(
    val itsInnerColor: Float4, // 	In principle premultiplied alpha (αR,αG,αB,α)
    val itsOuterColor: Float4, // 		but in practice fully opaque with α = 1 .
)
