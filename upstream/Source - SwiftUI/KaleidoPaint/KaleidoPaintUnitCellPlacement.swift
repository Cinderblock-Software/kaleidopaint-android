//	KaleidoPaintUnitCellPlacement.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import Metal

struct UnitCellPlacement {	//	placement of unit cell in drawing

	//	Image of the corner (0,0) ["lower-left corner"]
	//	of one copy of unit cell, in the drawing coordinates.
	//	Typically we'll record the copy of the unit cell that's
	//	closest to the drawing's center, but any copy is OK.
	var itsCorner: SIMD2<Double>

	//	Images of the unit cell's (1,0) ["horizontal"]
	//	and (0,1) ["vertical"] sides, expressed
	//	as translations in drawing coordinates.
	var itsTranslations: simd_double2x2 {
		didSet {
			recomputeMetric()
		}
	}

	//	Whenever itsTranslations gets set (except during init())
	//	its didSet observer will call recomputeMetric()
	//	to update itsMetricOfDet1 accordingly.
	//	We never need to update it manually.
	private(set) var itsMetricOfDet1: simd_double2x2

	init(defaultForWallpaperGroup wallpaperGroup: WallpaperGroup) {

		let theSquare = simd_double2x2(
			SIMD2<Double>(1.0, 0.0),
			SIMD2<Double>(0.0, 1.0)
		)
		let theRhombus6 = simd_double2x2(
			SIMD2<Double>(1.0,    0.0   ),
			SIMD2<Double>(0.5, 0.5*sqrt(3.0))
		)

		let theCorner: SIMD2<Double>
		let theUnscaledTranslations: simd_double2x2
		switch wallpaperGroup {
		
		case .wpgO:
			//	We could use a generic parallelogram for ○,
			//	but I decided to use theSquare instead.
			//	The user can then adjust the aspect ratio
			//	and shear as desired.
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theSquare

		case .wpg2222:
			//	We could use a generic parallelogram for 2222,
			//	but I decided to use theSquare instead.
			//	The user can then adjust the aspect ratio
			//	and shear as desired.
			theCorner = SIMD2<Double>(0.0, -0.25)
			theUnscaledTranslations = theSquare

		case .wpg333:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theRhombus6

		case .wpg442:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theSquare

		case .wpg632:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theRhombus6

		case .wpgS2222:
			theCorner = SIMD2<Double>(0.25, 0.0)
			theUnscaledTranslations = theSquare

		case .wpgS333:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theRhombus6

		case .wpgS442:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theSquare

		case .wpgS632:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theRhombus6

		case .wpg22S:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theSquare

		case .wpg2S22:
			theCorner = SIMD2<Double>(0.5, 0.0)
			theUnscaledTranslations = simd_double2x2(
				SIMD2<Double>(1.0, -1.0),
				SIMD2<Double>(1.0, +1.0)
			)

		case .wpg3S3:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theRhombus6

		case .wpg4S2:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theSquare

		case .wpgSS:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theSquare

		case .wpg22X:
			theCorner = SIMD2<Double>(0.0, 0.25)
			theUnscaledTranslations = theSquare

		case .wpgSX:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = simd_double2x2(
				SIMD2<Double>(1.0, -1.0),
				SIMD2<Double>(1.0, +1.0)
			)

		case .wpgXX:
			theCorner = SIMD2<Double>.zero
			theUnscaledTranslations = theSquare
		}

		//	Rescale the translations so that the unit cell
		//	has the desired area.
		let theRawUnitCellArea = theUnscaledTranslations.determinant	//	known to be > 0.0
		var theDesiredUnitCellArea = 0.25 * 0.25						//	also > 0.0
		if wallpaperGroup == .wpgSX {
		
			//	In order to get the group *× to have the same spacing
			//	between the mirror and/or glide reflection lines
			//	as ** and ××, and also to have the same aspect ratio,
			//	we need *× to have twice the default area.
			theDesiredUnitCellArea *= 2.0
		}
		if wallpaperGroup == .wpg2S22 {
		
			//	In order to get the group 2*22 to have the same spacing
			//	between the mirror and/or glide reflection lines
			//	as *2222, **, *×, ××, 22* and 22×, the same spacing
			//	between 2-fold gyration points as 2222,
			//	and also to have the same aspect ratio,
			//	we need 2*22 to have twice the default area.
			theDesiredUnitCellArea *= 0.5
		}
		let theScaleFactor = sqrt( theDesiredUnitCellArea / theRawUnitCellArea ) // => safe

		itsCorner = theCorner * theScaleFactor
		itsTranslations = theUnscaledTranslations * theScaleFactor

		//	Set a dummy metric so that this UnitCellPlacement
		//	will be "fully initialized" and then...
		itsMetricOfDet1 = matrix_identity_double2x2
		
		//	...immediately replace the dummy value
		//	with the metric that corresponds to itsTranslations.
		recomputeMetric()
	}


// MARK: -
// MARK: Metric

	private mutating func recomputeMetric() {
	
		if unitCellIsDegenerate() {
			itsMetricOfDet1 = matrix_identity_double2x2
			return
		}
		
		//	itsTranslations define a mapping from extended unit cell coordinates
		//	to drawing coordinates.  Isotropically rescale the mapping to be area-preserving.
		//	Algebraically, this means rescale it to have determinant 1.
		//	In effect this will map the unit cell to a unit-area parallelogram
		//	of the required shape.

		//	The check for UnitCellIsNondegenerate() should ensure
		//	that the determinant is never too close to zero.
		let theFactor = 1.0 / sqrt(fabs(itsTranslations.determinant))
		let theRescaledTranslations = theFactor * itsTranslations
		
		//	The spline-drawing code will want to take vectors
		//	(x,y) and (x',y') in the unit cell, transfer them
		//	to the "unit-area parallelogram" described above,
		//	and take their dot product there.  Algebraically
		//	this may be written
		//
		//		(x y) (a b) (a c) (x')
		//		      (c d) (b d) (y')
		//
		//	For both computational and conceptual simplicity,
		//	we may pre-multiply those two matrices in the center
		//	of that product to get a metric that expresses
		//	the unit-area parallelogram's geometry while still
		//	working in the standard square unit cell's coordinate system.
		//
		//		Note #1:  The order of the factors in the line below
		//		is the opposite of their order in the comment above,
		//		because Swift's matrix multiplication operator '*'
		//		uses column-major matrices and right-to-left matrix actions.
		//
		//		Note #2:  Because theRescaledTranslations have determinant 1,
		//		the metric will also have determinant 1.
		//
		itsMetricOfDet1 = theRescaledTranslations.transpose * theRescaledTranslations
	}
	
	func unitCellIsDegenerate() -> Bool {

		//	Unit cell non-degeneracy constraints
		let theMinSideLength	=  0.015625	//	2⁻⁶,  in drawing units
		let theMaxSideLength	= 64.0		//	2⁺⁶,  in drawing units
		let theMaxSideRatio		=  8.0		//	For rhombic groups,
											//		the side ratio is always 1:1.
											//	For the remaining rectangular groups,
											//		the ShapePanel allows for an aspect ratio
											//		anywhere between 4:1 and 1:4.
											//	For the two remaining groups (○ and 2222),
											//		the ShapePanel allows for an aspect ratio
											//		anywhere between 4:1 and 1:4 along with
											//		a shear between -2 and +2, which can further
											//		increase the ratio of the side lengths.
											//	Thus the largest allowable ratio of side lengths
											//	is sqrt(4² + 2²) = sqrt(20) = 4.47… .
											//	But let's set theMaxSideRatio = 8.0 to allow
											//	some slack, in case we later change those limits
											//	in the ShapePanel.  (Yes, I know, I should read
											//	those values and compute theMaxSideRatio based
											//	on them.  But I don't want to add the extra clutter,
											//	given that the sole purpose of this check
											//	on theMaxSideRatio is to make sure that nothing
											//	has gone disasterously wrong.)
		//	I think theMinSine = 0.5 may have been a legacy value
		//	from when an older version of KaleidoPaint was using
		//	a shortest pair of generating translations
		//	(that is, a shortest pair of sides), in which case
		//	the angle between them is always at least 30°
		//	and thus the sine is always at least 1/2.
		//	But the current version of KaleidoPaint doesn't
		//	always use the shortest translations.  For rhombic groups
		//	it instead uses "scissors-like" generating translations.
		//	That is, it uses two generators of equal length
		//	which respect the symmetry group's mirror and glide reflections.
		//	Such scissors-translations can easily have an angle of less than 30°.
		//
		//	For the rhombic groups, if the maximum aspect ratio is 4,
		//	any min-sine value less than 1/√(4² + 1²) = 0.24… should be fine.
		let theMinSine			=  0.1	//	had been 0.5 in legacy version

		//	Note the lengths of the two translation vectors.
		let theLengths = [length(itsTranslations[0]), length(itsTranslations[1])]

		//	Make sure each translation vector is neither too long nor too short.
		for theLength in theLengths {
			if theLength < theMinSideLength
			|| theLength > theMaxSideLength {
				return true
			}
		}
		
		//	Make sure the ratio of the two translation lengths
		//	isn't too great or too small.
		if theLengths[0] > theMaxSideRatio * theLengths[1]
		|| theLengths[1] > theMaxSideRatio * theLengths[0] {
			return true
		}
		
		//	Make sure the included angle θ isn't too close to either 0° or 180°.
		//
		//	There are two ways to think about computing the sine;
		//	both lead to the same calculation.  In both cases,
		//	let u and v be the unit vectors in the directions
		//	of the two translations.
		//
		//	Method #1.  Compute
		//
		//		sin(θ)	= area of rhombus with sides u and v
		//				= det(u,v)
		//
		//	Method #2.  Rotate u one-quarter turn counterclockwise
		//	and dot it with v to get sin(θ).
		//
		let theUnitVectors = simd_double2x2(
			itsTranslations[0] / theLengths[0],	//	theLengths[0] ≥ theMinSideLength > 0.0
			itsTranslations[1] / theLengths[1]	//	theLengths[1] ≥ theMinSideLength > 0.0
		)
		let theSine = theUnitVectors.determinant
		if theSine < theMinSine {
			return true
		}
		
		return false
	}
	
// MARK: -
// MARK: Transformations

	mutating func snapToViewAlignment() {

		//	Sine of the largest rotation angle that
		//	the snap-to-view feature will snap to zero.
		//
		//	0.02 is very subtle but usable.
		//
		//	0.04 makes snapping easier, but could conceivably
		//	     annoy people who want a slightly tilted drawing
		//	     for artistic reasons.
		//
		let theSnapToViewEpsilon = 0.04

		var theTranslations: [SIMD2<Double>] = []
		
		theTranslations.append(normalize(itsTranslations[0]))
		theTranslations.append(normalize(itsTranslations[1]))
		theTranslations.append(normalize(itsTranslations[1] - itsTranslations[0]))
		
		//	Consider each vector rotated by π/2.  That way we need
		//	to compare only to the horizontal, not to the vertical.
		//	In square and hexagonal lattices, the resulting
		//	six translations include all mirror lines.
		
		let theQuarterTurn = matrix_double2x2(
			SIMD2<Double>( 0.0, 1.0),
			SIMD2<Double>(-1.0, 0.0)
		)
		
		theTranslations.append( theQuarterTurn * theTranslations[0] )	//	right-to-left action
		theTranslations.append( theQuarterTurn * theTranslations[1] )	//	right-to-left action
		theTranslations.append( theQuarterTurn * theTranslations[2] )	//	right-to-left action

		for theTranslation in theTranslations {
		
			//	Negate theTranslation if necessary so that
			//	its x-component will be non-negative.
			let thePosTranslation = (
				theTranslation[0] >= 0.0 ?
					 theTranslation :
					-theTranslation
			)

			//	thePosTranslation almost aligns with the horizontal
			//	iff the sine of its angle is small.  Because the vector
			//	is normalized, the sine is simply theTranslation[1].
			if fabs(thePosTranslation[1]) < theSnapToViewEpsilon {

				//	Note the cosine and sine of the required rotation.
				let cosθ =  thePosTranslation[0]
				let sinθ = -thePosTranslation[1]

				let theRotation = simd_double2x2(
					SIMD2<Double>( cosθ, sinθ),
					SIMD2<Double>(-sinθ, cosθ)
				)
				
				//	Rotate both unit cell translation vectors.
				itsTranslations[0] = theRotation * itsTranslations[0]	//	right-to-left action
				itsTranslations[1] = theRotation * itsTranslations[1]	//	right-to-left action

				//	We can snap to at most one direction, so we're done.
				//	(And because we've changed itsTranslations,
				//	the theTranslations are no longer valid in any case.)
				//
				return
			}
		}
	}
	
	mutating func transform(
		using transformation: simd_double3x2) {	//	the last column of the 3×3 matrix
												//	(using left-to-right matrix actions)
												//	isn't explicitly included, because
												//	implicitly it's always (0,0,1)
		
		itsCorner
			= transformation	//	right-to-left matrix action
			* SIMD3<Double>(itsCorner, 1.0)
		
		//	itsTranslations[i] is a "horizontal" vector (x,y,0).
		//	In effect it's the difference of two points,
		//	so it responds to tbe transformation's dilational/rotational part,
		//	but not to its translational part.

		itsTranslations[0]
			= transformation	//	right-to-left matrix action
			* SIMD3<Double>(itsTranslations[0], 0.0)
			
		itsTranslations[1]
			= transformation	//	right-to-left matrix action
			* SIMD3<Double>(itsTranslations[1], 0.0)
	}
	
	mutating func centerTheUnitCell() {
	
		//	Move the unit cell so that it contains
		//	the origin (0,0) of drawing coordinates.
		
		//	Express the drawing-coordinate origin (0,0) in unit cell coordinates,
		//
		//		(0,0) = itsCorner
		//			  +  a * itsTranslations[0]
		//			  +  b * itsTranslations[1]
		//
		//	or, thinking of (a,b) as a row vector and itsTranslations as a 2×2 matrix,
		//
		//		(0,0) - itsCorner = (a,b) * itsTranslations		//	left-to-right matrix action
		//
		//	Using right-to-left matrix actions (as Swift prefers) this equation becomes
		//
		//		(0,0) - itsCorner = itsTranslations * (a,b)		//	right-to-left matrix action
		//
		//	which we may solve for
		//
		//		  theDrawingOriginInUnitCellCoordinates
		//		= (a,b)
		//		= itsTranslations⁻¹ * (-itsCorner)
		//

		precondition(
			itsTranslations.determinant > 0.0,
			"non-positive determinant")

		let theDrawingOriginInUnitCellCoordinates
			= itsTranslations.inverse
			* -itsCorner

		//	The floor of each of the view-origin's unit cell coordinates
		//	tells us by what integer multiple of each unit cell translation vector
		//	we need to shift the unit cell's origin.
		//	(Draw a picture and this will be clear!)
		//	If both of the origin's unit cell coordinates have floor 0,
		//	then we don't need to shift the cell origin at all.

		let theMultiples = floor(theDrawingOriginInUnitCellCoordinates)
		
		itsCorner += itsTranslations * theMultiples	//	right-to-left matrix action
	}
}


struct UnitCellShape: Equatable {

	//	itsAspectRatio = itsTranslations[1]
	//				   / itsTranslations[0]
	//
	var aspectRatio: Double
	
	//	When the unit cell is a rectangle,
	//	itsTranslations[1] is orthogonal to itsTranslations[0].
	//	To create a generic parallelogram, we may add a multiple
	//	of itsTranslations[0] to itsTranslations[1], like this
	//
	//		itsTranslations[1] += shear * itsTranslations[0]
	//
	var shear: Double
}
