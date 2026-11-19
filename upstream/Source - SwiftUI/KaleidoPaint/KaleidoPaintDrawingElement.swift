//	KaleidoPaintDrawingElement.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import Metal


//	We implement DrawingElement as a class (not a struct) so that
//	we can keep a reliable reference to a selected DrawingElement.
//	In particular, when the user changes, say, the selected element's
//	color, that will change the color of the instance in itsElements
//	as well (not just the color of a copy, as would be the case with a struct).
//	A second advantage of implementing DrawingElement as a class
//	is that we can then implement Dot, Curve and Fill as subclasses.
//
@Observable class DrawingElement: Equatable {

	var itsColor: LinearDisplayP3Color


	init(
		color: LinearDisplayP3Color
	) {
		itsColor = color
	}

	static func == (lhs: DrawingElement, rhs: DrawingElement) -> Bool {
		return lhs === rhs	//	same instance
	}

	func hitControlHandle(
		touchPointInExtendedUnitCellCoordinates: SIMD2<Double>,
		wallpaperGroup: WallpaperGroup,
		metricOfDet1: simd_double2x2,
		fillMarkerRadius: Double	//	used only for Fills
	) -> ControlHandleHit?
	{
		//	Each subclass (Dot, Curve and Fill) overrides
		//	this method to specify which control handle(s)
		//	need(s) to be tested.  The subclass then calls
		//	hitImageOfControlHandle() to decide whether
		//	some image of the given control handle(s) does
		//	indeed get hit.
		
		preconditionFailure("Internal error:  subclass must override this method")
	}

	func hitImageOfControlHandle(
		touchPointInExtendedUnitCellCoordinates: SIMD2<Double>,
		controlHandleCenter: SIMD2<Double>,	//	in strict unit cell coordinates
		controlHandleMeanRadius: Double,	//	in unit cell coordinates
		splineNode: SplineNode?,
		wallpaperGroup: WallpaperGroup,
		metricOfDet1: simd_double2x2
	) -> ControlHandleHit?
	{
	
		//	Test the images of the control handle
		//	under the action of the WallpaperGroup
		//	to see whether the tap hits any of them.
		//	If several images sit close to each other,
		//	select the image closest to the tap point.
		var thePossibleHitControlHandle: ControlHandleHit?
		var theSmallestTapError = Double.infinity

		for theSymmetry in wallpaperGroup.torusGroup.itsElements {
		
			let theImageCenter3
				= theSymmetry.itsMatrix
				* SIMD3<Double>(controlHandleCenter, 1.0)	//	right-to-left matrix action
			let theImageCenter = SIMD2<Double>(theImageCenter3[0], theImageCenter3[1])
			
			//	WARNING:  Splitting theRawOffset into theIntegerOffset
			//	and theFractionalOffset implicitly selects
			//	the control-handle image that's closest to the tap point
			//	relative to a square metric on the unit cell,
			//	which might not be right in rare cases where
			//	the unit cell is a very narrow parallelogram.
			//	(Hmmm... unless we doing some sort of basis simplication
			//	progess to keep the unit cell's acute angle from ever
			//	dropping below π/3.)
			//
			let theRawOffset = touchPointInExtendedUnitCellCoordinates - theImageCenter
			let theIntegerOffset = SIMD2<Double>(round(theRawOffset[0]), round(theRawOffset[1]))
			let theFractionalOffset = theRawOffset - theIntegerOffset

			//	For brevity, write theFractionalOffset as simply δ.
			//
			//	Computing δ₀² + δ₁² would give us |δ|² (the squared length of δ)
			//	relative to a square unit cell geometry, which typically isn't
			//	what we want.  Instead, we want to compute |δ|² relative
			//	to the unit cell's parallelogram shape, as it appears
			//	in the drawing itself.  Fortunately this is easy to do
			//	using the metricOfDet1, written here as g :
			//
			//		( δ₀  δ₁ )( g₀₀  g₀₁ )(δ₀)
			//		          ( g₁₀  g₁₁ )(δ₁)
			//
			let theTapError = sqrt(
				theFractionalOffset[0] * metricOfDet1[0][0] * theFractionalOffset[0]
			  + theFractionalOffset[0] * metricOfDet1[0][1] * theFractionalOffset[1]
			  + theFractionalOffset[1] * metricOfDet1[1][0] * theFractionalOffset[0]
			  + theFractionalOffset[1] * metricOfDet1[1][1] * theFractionalOffset[1] )

			//	Let the hit radius (in which taps on a control handle image
			//	are accepted) be a multiple of the controlHandleMeanRadius.
			let theHitRadiusFactor = 8.0
			
			if theTapError <= theHitRadiusFactor * controlHandleMeanRadius
			&& theTapError < theSmallestTapError {
			
				//	theForwardSymmetry takes the control point's
				//	home position to its hit image.
				var theForwardSymmetry = theSymmetry.itsMatrix
				theForwardSymmetry[2][0] += theIntegerOffset[0]
				theForwardSymmetry[2][1] += theIntegerOffset[1]

				//	theForwardSymmetry takes the control point's
				//	hit image to its home position.
				let theBackwardSymmetry = theForwardSymmetry.inverse

				thePossibleHitControlHandle
					= ControlHandleHit(
						itsElement: self,
						itsNode: splineNode,
						itsHomeCenter: controlHandleCenter,
						itsHitCenter: theImageCenter + theIntegerOffset,
						itsSymmetry: theBackwardSymmetry,
						itsTapError: theTapError)
			
				theSmallestTapError = theTapError
			}
		}
		
		return thePossibleHitControlHandle
	}
}

struct ControlHandleHit {

	let itsElement: DrawingElement
	let itsNode: SplineNode?	//	non-nil iff itsElement is a Curve

	//	The control point's home position, which may or may not
	//	be the center of the control point's image that got hit.
	let itsHomeCenter: SIMD2<Double>	//	in extended unit cell coordinates

	//	The center of the control point's image that got hit,
	//	which may or may not be the control point's home position.
	let itsHitCenter: SIMD2<Double>		//	in extended unit cell coordinates

	//	The symmetry of the drawing that takes itsHitCenter to itsHomeCenter.
	let itsSymmetry: simd_double3x3
	
	//	How far was the user's tap from the control handle's center?
	//	Each control handle accepts taps within a disk whose radius
	//	is theHitRadiusFactor times the radius of the control handle itself.
	//	When several control handles sit close to each other,
	//	we'll let the tap select the closest one.
	//
	let itsTapError: Double	//	relative to the unit cell's parallelogram shape
}


// MARK: -
// MARK: Vector computations

func unitLengthVector(
	v: SIMD2<Double>,	//	vector in unit cell coordinates
	metricOfDet1 m: simd_double2x2
) -> SIMD2<Double> {

	//	Relative to the metric m, v has squared length
	//
	//		( v₀ v₁ )( m₀₀ m₀₁ )( v₀ )
	//		         ( m₁₀ m₁₁ )( v₁ )
	//
	let theLengthSquared = v[0] * m[0][0] * v[0]
						 + v[0] * m[0][1] * v[1]
						 + v[1] * m[1][0] * v[0]
						 + v[1] * m[1][1] * v[1]
	
	let theUnitLengthVector: SIMD2<Double> = (
		theLengthSquared > 0.0 ?
			v / sqrt(theLengthSquared) :
			SIMD2<Double>(1.0, 0.0)	//	arbitrary fallback
	)
	
	return theUnitLengthVector
}

func orthogonalVector(
	to v: SIMD2<Double>,			//	vector in unit cell coordinates
	metricOfDet1 m: simd_double2x2	//	metric with det(m) = 1
) -> SIMD2<Double> {	//	returns w with <v,w> = 0 and |w|² = |v|²

	//	We want to find a vector w that's orthogonal to the given vector v,
	//	relative to the metric m.  That is,
	//
	//		( w₀ w₁ )( m₀₀ m₀₁ )( v₀ ) = 0
	//		         ( m₁₀ m₁₁ )( v₁ )
	//
	//	If we compute the partial product
	//
	//		( pp₀ ) = ( m₀₀ m₀₁ )( v₀ )
	//		( pp₁ )   ( m₁₀ m₁₁ )( v₁ )
	//
	//	then we may set
	//
	//		( w₀ w₁ ) = ( -pp₁, pp₀ ).
	//
	//	In other words,
	//
	//		( w₀ ) = ( 0 -1 )( m₀₀ m₀₁ )( v₀ )
	//		( w₁ )   ( 1  0 )( m₁₀ m₁₁ )( v₁ )
	//
	//	Technical note:  It seems likely that w will always
	//	be a 90° counterclockwise (never clockwise) rotation of v,
	//	relative to the usual coordinate conventions,
	//	but I haven't proved this and we don't rely on it.
	
	let pp₀ = m[0][0] * v[0]
			+ m[0][1] * v[1]
		   
	let pp₁ = m[1][0] * v[0]
			+ m[1][1] * v[1]
	
	let w = SIMD2<Double>(-pp₁, pp₀)

	//	The squared length of w, in drawing-space coordinates, is
	//
	//		|w|² = ( w₀ w₁ )( m₀₀ m₀₁ )( w₀ )
	//		                ( m₁₀ m₁₁ )( w₁ )
	//
	//	Substituting in the formula for ( w₀ w₁ ) from above gives
	//
	//		|w|²
	//	  =
	//		( v₀ v₁ )( m₀₀ m₁₀ )( 0  1 )  ( m₀₀ m₀₁ )  ( 0 -1 )( m₀₀ m₀₁ )( v₀ )
	//		         ( m₀₁ m₁₁ )(-1  0 )  ( m₁₀ m₁₁ )  ( 1  0 )( m₁₀ m₁₁ )( v₁ )
	//	  =
	//		( v₀ v₁ )( m₀₀ m₁₀ )( 0  1 )  ( m₀₁ -m₀₀ )  ( m₀₀ m₀₁ )( v₀ )
	//		         ( m₀₁ m₁₁ )(-1  0 )  ( m₁₁ -m₁₀ )  ( m₁₀ m₁₁ )( v₁ )
	//	  =
	//		( v₀ v₁ )( m₀₀ m₁₀ )  ( m₁₁ -m₁₀ )  ( m₀₀ m₀₁ )( v₀ )
	//		         ( m₀₁ m₁₁ )  (-m₀₁  m₀₀ )  ( m₁₀ m₁₁ )( v₁ )
	//	  =
	//		( v₀ v₁ )( det(m)  0    )  ( m₀₀ m₀₁ )( v₀ )
	//		         (   0   det(m) )  ( m₁₀ m₁₁ )( v₁ )
	//	  =
	//		det(m) ( v₀ v₁ )( m₀₀ m₀₁ )( v₀ )
	//		                ( m₁₀ m₁₁ )( v₁ )
	//	  =
	//	    det(m) |v|²
	//
	//	Because we are given a metric with det(m) = 1,
	//	this proves that |w|² = |v|².
	
	return w
}
