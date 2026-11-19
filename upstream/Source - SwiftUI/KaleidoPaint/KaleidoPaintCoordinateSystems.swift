//	KaleidoPaintCoordinateSystems.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt


//	Coordinate systems
//
//	KaleidoPaint uses three coordinate systems:
//
//		Unit cell coordinates
//			run from 0 to 1 along each edge of the unit cell,
//			with the origin at one corner of the unit cell.
//			Personally I visualize the origin at the lower left,
//			the first coordinate running to the right, and
//			the second coordinate running upwards, but
//			of course how one visualizes it is irrelevant,
//			just so everybody agrees on how it maps into the drawing.
//			Note #1:  The unit cell's x- and y-coordinates
//			are orthogonal when viewing the unit cell's square texture,
//			but typically not orthogonal when viewing the unit cell
//			as a parallelogram in the drawing.
//			Note #2:  Restricting the coordinates to [0,1]×[0,1]
//			parameterizes one copy of the unit cell, but it's often
//			more useful to let coordinates in [-∞,∞]×[-∞,∞]
//			parameterize the whole tiling, as "extended unit cell coordinates".
//
//		Drawing coordinates
//			define an infinite Euclidean plane,
//			tiled by repeating images of the unit cell.
//
//		View coordinates
//			parameterize the view that we're drawing into
//			and always run from -1 to +1 in each direction,
//			regardless of the view's true aspect ratio
//			(so the scale in the x-direction typically differs
//			from the scale in the y-direction).  In other words,
//			this is Metal's fundamental coordinate system.
//
//	The "page rectangle" connects view coordinates to drawing and unit cell coordinates.
//	The page rectangle's vertices
//
//	  - sit at (±1, ±1) in view coordinates,
//			to indicate that the page fills the whole view,
//
//	  - sit at (±w/2, ±h/2) in drawing coordinates,
//			with w and h chosen to satisfy two conditions:
//
//			1.	the aspect ratio w/h agrees with the view's physical
//				aspect ratio on the user's display, and
//
//			2.	the page has diagonal length 1 in drawing coordinates,
//				that is, w² + h² = 1,
//
//			thus defining what portion of the drawing you see within the page,
//			and ensuring that the scale of the drawing remains roughly the same
//			even when the aspect ratio changes.
//
//	  - take positions in extended unit cell coordinates
//			according to how the square unit cell maps
//			to a parallelogram in drawing coordinates.
//
//	Note:  As the user reshapes the view, the page's corners remain
//	at (±1, ±1) in view coordinates, while their position (±w/2, ±h/2)
//	in drawing coordinates changes to accommodate the new aspect ratio.


func convertPageSizeToDrawingCoordinates(
	_ width: Double,	//	input, in any units
	_ height: Double	//	input, in any units
) -> (Double, Double) {	//	drawing width and height in drawing coordinates (see above)

	//	As explained in the extended comment "Coordinate systems" above,
	//	we want to find w and h satisfying
	//
	//			w / h == width / height
	//	and
	//			w² + h² == 1
	//

	let theDiagonal = sqrt(width*width + height*height)
	let w: Double
	let h: Double
	if theDiagonal > 0.0 {
		w = width  / theDiagonal
		h = height / theDiagonal
	}
	else
	{
		w = 1.0
		h = 1.0
	}
	
	return (w, h)
}

func convertDisplayCoordinatesToDrawingCoordinates(
	_ pointInDisplayCoordinates: DisplayPoint
) ->  SIMD2<Double> {	//	returns the same point in drawing coordinates
						//		(see the extended comment "Coordinate systems"
						//		at the top of this file)

	if pointInDisplayCoordinates.viewWidth  == 0.0
	|| pointInDisplayCoordinates.viewHeight == 0.0 {
		
		assertionFailure("convertDisplayCoordinatesToDrawingCoordinates() received zero-area view.")
		return SIMD2<Double>.zero
	}

	//	theDrawingWidth and theDrawingHeight will be the same for all points,
	//	-- so we're wasting CPU cycles here -- but the redundant computation
	//	is a small price to pay to keep the code clean.
	let (theDrawingWidth, theDrawingHeight)	//	in drawing coordinates
		= convertPageSizeToDrawingCoordinates(
			pointInDisplayCoordinates.viewWidth,
			pointInDisplayCoordinates.viewHeight)
	
	let theDrawingCoordinates = SIMD2<Double>(
		(pointInDisplayCoordinates.x / pointInDisplayCoordinates.viewWidth  - 0.5) * theDrawingWidth,
		(pointInDisplayCoordinates.y / pointInDisplayCoordinates.viewHeight - 0.5) * theDrawingHeight
	)
	
	return theDrawingCoordinates
}

func convertDrawingCoordinatesToDisplayCoordinates(
	_ pointInDrawingCoordinates: SIMD2<Double>,
	viewWidth: Double,
	viewHeight: Double
) -> DisplayPoint {

	if viewWidth  == 0.0
	|| viewHeight == 0.0 {
		
		assertionFailure("convertDrawingCoordinatesToDisplayCoordinates() received zero-area view.")
		return DisplayPoint(x: 0.0, y: 0.0, viewWidth: viewWidth, viewHeight: viewHeight)
	}

	let (theDrawingWidth, theDrawingHeight)	//	in drawing coordinates
		= convertPageSizeToDrawingCoordinates(viewWidth, viewHeight)
	
	let theDisplayPoint = DisplayPoint(
		x: (0.5 + (pointInDrawingCoordinates[0] / theDrawingWidth )) * viewWidth,
		y: (0.5 + (pointInDrawingCoordinates[1] / theDrawingHeight)) * viewHeight,
		viewWidth: viewWidth,
		viewHeight: viewHeight)
	
	return theDisplayPoint
}

func convertDisplayTranslationToDrawingTranslation(
	_ translationInDisplayCoordinates: DisplayPointMotion
) ->  SIMD2<Double> {	//	returns the same translation in drawing coordinates
						//		(see the extended comment "Coordinate systems"
						//		at the top of this file)

	if translationInDisplayCoordinates.viewWidth  == 0.0
	|| translationInDisplayCoordinates.viewHeight == 0.0 {
		
		assertionFailure("convertDisplayTranslationToDrawingTranslation() received zero-area view.")
		return SIMD2<Double>.zero
	}

	//	theDrawingWidth and theDrawingHeight will be the same for all points,
	//	-- so we're wasting CPU cycles here -- but the redundant computation
	//	is a small price to pay to keep the code clean.
	let (theDrawingWidth, theDrawingHeight)	//	in drawing coordinates
		= convertPageSizeToDrawingCoordinates(
			translationInDisplayCoordinates.viewWidth,
			translationInDisplayCoordinates.viewHeight)
	
	let theTranslationInDrawingCoordinates = SIMD2<Double>(
		(translationInDisplayCoordinates.Δx / translationInDisplayCoordinates.viewWidth ) * theDrawingWidth,
		(translationInDisplayCoordinates.Δy / translationInDisplayCoordinates.viewHeight) * theDrawingHeight
	)
	
	return theTranslationInDrawingCoordinates
}


func convertDrawingCoordinatesToExtendedUnitCellCoordinates(
	_ pointInDrawingCoordinates: SIMD2<Double>,
	unitCellPlacement: UnitCellPlacement
) -> SIMD2<Double> {	//	returns the same point in extended unit cell coordinates
						//		(see the extended comment "Coordinate systems"
						//		at the top of this file)
						
	//	Express the point (x,y) relative
	//	to the unit cell's lower-left corner.
	let theOffsetPoint = pointInDrawingCoordinates - unitCellPlacement.itsCorner
	
	//	Extended unit cell coordinates express theOffsetPoint
	//	as a linear combination of the unit cell's translation vectors,
	//
	//		                                              (  unit cell  )
	//		(theOffsetPoint) = (theExtendedUnitCellCoords)( translation )
	//		                                              (   vectors   )
	//
	let thePointInExtendedUnitCellCoordinates: SIMD2<Double>
	if unitCellPlacement.itsTranslations.determinant != 0.0 {

		thePointInExtendedUnitCellCoordinates
			= unitCellPlacement.itsTranslations.inverse * theOffsetPoint
			//	Note:  The order of the factors here is the reverse
			//	of the order in the comment above, to accommodate Swift's
			//	column-major right-to-left matrix multiplication convention.
	
	} else {	//	should never occur
	
		assertionFailure("convertDrawingCoordinatesToExtendedUnitCellCoordinates received a degenerate UnitCellPlacement")
		//	The assertionFailure() will break to the debugger
		//	when running under Xcode, but in the final released app
		//	execution will continue, so we need to do something harmless.
		thePointInExtendedUnitCellCoordinates = theOffsetPoint
	}
	
	return thePointInExtendedUnitCellCoordinates
}

func convertExtendedUnitCellCoordinatesToDrawingCoordinates(
	_ pointInExtendedUnitCellCoordinates: SIMD2<Double>,
	unitCellPlacement: UnitCellPlacement
) -> SIMD2<Double> {

	//	Compute
	//
	//	thePointInDrawingCoordinates =
	//
	//		(unit cell corner)
	//	  +
	//	                                        (  unit cell  )
	//		(pointInExtendedUnitCellCoordinates)( translation )
	//	                                        (   vectors   )
	//
	let thePointInDrawingCoordinates
		= unitCellPlacement.itsCorner
		+ unitCellPlacement.itsTranslations * pointInExtendedUnitCellCoordinates
	//
	//	Note:  The order of the factors here is the reverse
	//	of the order in the comment above, to accommodate Swift's
	//	column-major right-to-left matrix multiplication convention.
	
	return thePointInDrawingCoordinates
}

func convertExtendedUnitCellCoordinatesToStrictUnitCellCoordinates(
	_ pointInExtendedUnitCellCoordinates: SIMD2<Double>
) -> SIMD2<Double> {	//	returns the same point in strict unit cell coordinates
						//		(see the extended comment "Coordinate systems"
						//		at the top of this file)

	//	Convert from extended unit cell coordinates
	//	to strict unit cell coordinates, in the range [0,1].
	
	let thePointInStrictUnitCellCoordinates =
		pointInExtendedUnitCellCoordinates
		- floor(pointInExtendedUnitCellCoordinates)

	return thePointInStrictUnitCellCoordinates
}

func convertDisplayCoordinatesToExtendedUnitCellCoordinates(
	_ pointInDisplayCoordinates: DisplayPoint,
	unitCellPlacement: UnitCellPlacement
) -> SIMD2<Double> {	//	returns the same point in extended unit cell coordinates
						//		(see the extended comment "Coordinate systems"
						//		at the top of this file)

	let thePointInDrawingCoordinates
		= convertDisplayCoordinatesToDrawingCoordinates(
			pointInDisplayCoordinates)
			
	let thePointInExtendedUnitCellCoordinates
		= convertDrawingCoordinatesToExtendedUnitCellCoordinates(
			thePointInDrawingCoordinates,
			unitCellPlacement: unitCellPlacement)
	
	return thePointInExtendedUnitCellCoordinates
}

func convertDisplayCoordinatesToStrictUnitCellCoordinates(
	_ pointInDisplayCoordinates: DisplayPoint,
	unitCellPlacement: UnitCellPlacement
) -> SIMD2<Double> {	//	returns the same point in strict unit cell coordinates
						//		(see the extended comment "Coordinate systems"
						//		at the top of this file)

	let thePointInDrawingCoordinates
		= convertDisplayCoordinatesToDrawingCoordinates(
			pointInDisplayCoordinates)
			
	let thePointInExtendedUnitCellCoordinates
		= convertDrawingCoordinatesToExtendedUnitCellCoordinates(
			thePointInDrawingCoordinates,
			unitCellPlacement: unitCellPlacement)
	
	let thePointInStrictUnitCellCoordinates
		= convertExtendedUnitCellCoordinatesToStrictUnitCellCoordinates(
			thePointInExtendedUnitCellCoordinates)
	
	return thePointInStrictUnitCellCoordinates
}

func convertExtendedUnitCellCoordinatesToDisplayCoordinates(
	_ pointInExtendedUnitCellCoordinates: SIMD2<Double>,
	unitCellPlacement: UnitCellPlacement,
	viewWidth: Double,	//	in pixels or points, either is fine
	viewHeight: Double	//		just so viewWidth and viewHeight are consistent
) -> DisplayPoint {		//	returns the same point as a DisplayPoint
					
	let thePointInDrawingCoordinates
		= convertExtendedUnitCellCoordinatesToDrawingCoordinates(
			pointInExtendedUnitCellCoordinates,
			unitCellPlacement: unitCellPlacement)
	
	let thePointInDisplayCoordinates
		= convertDrawingCoordinatesToDisplayCoordinates(
			thePointInDrawingCoordinates,
			viewWidth: viewWidth,
			viewHeight: viewHeight)
	
	return thePointInDisplayCoordinates
}
