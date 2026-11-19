//	KaleidoPaintBrushstroke.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import Metal


//	This class includes Dot and Curves but excludes Fills.
//	"Brushstroke" isn't a good name for it,
//	but I couldn't think of a better one.

class Brushstroke: DrawingElement {
	
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
	var itsThickness: Double

	init(
		color: LinearDisplayP3Color
			= LinearDisplayP3Color(r: 1.0, g: 0.0, b: 1.0, a: 1.0),
		thickness: Double
	) {
	
		itsThickness = thickness
		
		super.init(color: color)
	}

	func render(
		renderEncoder: MTLRenderCommandEncoder,
		metricOfDet1: simd_double2x2,
		scratchBuffer: UnsafeMutablePointer<SIMD2<Float32>>,	//	guaranteed to be big enough
		symmetryCount: Int
	) {
		preconditionFailure("Subclass must override Brushstroke.render()")
	}
}
