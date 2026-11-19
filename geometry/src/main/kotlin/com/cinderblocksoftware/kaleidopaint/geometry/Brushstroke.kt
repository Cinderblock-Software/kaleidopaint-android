// Ported from KaleidoPaintBrushstroke.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

//	This class includes Dot and Curves but excludes Fills.
//	"Brushstroke" isn't a good name for it,
//	but I couldn't think of a better one.

open class Brushstroke(
    color: LinearDisplayP3Color = LinearDisplayP3Color(r = 1.0, g = 0.0, b = 1.0, a = 1.0),
    thickness: Double,
) : DrawingElement(color = color) {

    //	Nominal dot or curve thickness ( = brush thickness )
    //	in unit cell coordinates.  In practice the thickness
    //	will be adjusted so that each dot will be a circle
    //	and each curve will have constant width, after
    //	the mapping into drawing space.  In other words,
    //	a dot gets rendered as an ellipse in the unit cell
    //	so that it comes out as a perfect circle in the drawing.
    //	The ellipse's major and minor radii have geometric mean
    //	equal to itsThickness.  Curves get rendered similarly.
    //
    var itsThickness: Double = thickness

    //	Port note:  renderEncoder stands in for Metal's MTLRenderCommandEncoder.
    //	See BrushstrokeRenderEncoder.kt.
    open fun render(
        renderEncoder: BrushstrokeRenderEncoder,
        metricOfDet1: Double2x2,
        scratchBuffer: VertexScratchBuffer, // 	guaranteed to be big enough
        symmetryCount: Int,
    ) {
        preconditionFailure("Subclass must override Brushstroke.render()")
    }
}
