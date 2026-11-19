// Ported from KaleidoPaintUnitCellPlacement.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.sqrt

//	Port note:  In Swift a UnitCellPlacement is a struct, so assigning one
//	makes a copy.  Here it is a class;  call copy() wherever
//	the original relies on getting its own copy.
//
class UnitCellPlacement( //	placement of unit cell in drawing
    defaultForWallpaperGroup: WallpaperGroup
) {

    //	Image of the corner (0,0) ["lower-left corner"]
    //	of one copy of unit cell, in the drawing coordinates.
    //	Typically we'll record the copy of the unit cell that's
    //	closest to the drawing's center, but any copy is OK.
    var itsCorner: Double2

    //	Images of the unit cell's (1,0) ["horizontal"]
    //	and (0,1) ["vertical"] sides, expressed
    //	as translations in drawing coordinates.
    var itsTranslations: Double2x2
        get() = itsTranslationsStorage
        set(value) {
            itsTranslationsStorage = value
            recomputeMetric() //	Swift's didSet
        }

    private var itsTranslationsStorage: Double2x2

    //	Whenever itsTranslations gets set (except during init())
    //	its didSet observer will call recomputeMetric()
    //	to update itsMetricOfDet1 accordingly.
    //	We never need to update it manually.
    var itsMetricOfDet1: Double2x2
        private set

    init {
        val wallpaperGroup = defaultForWallpaperGroup

        val theSquare =
            Double2x2(
                Double2(1.0, 0.0),
                Double2(0.0, 1.0),
            )
        val theRhombus6 =
            Double2x2(
                Double2(1.0, 0.0),
                Double2(0.5, 0.5 * sqrt(3.0)),
            )

        val theCorner: Double2
        val theUnscaledTranslations: Double2x2
        when (wallpaperGroup) {
            WallpaperGroup.wpgO -> {
                //	We could use a generic parallelogram for ○,
                //	but I decided to use theSquare instead.
                //	The user can then adjust the aspect ratio
                //	and shear as desired.
                theCorner = Double2.zero
                theUnscaledTranslations = theSquare
            }

            WallpaperGroup.wpg2222 -> {
                //	We could use a generic parallelogram for 2222,
                //	but I decided to use theSquare instead.
                //	The user can then adjust the aspect ratio
                //	and shear as desired.
                theCorner = Double2(0.0, -0.25)
                theUnscaledTranslations = theSquare
            }

            WallpaperGroup.wpg333 -> {
                theCorner = Double2.zero
                theUnscaledTranslations = theRhombus6
            }

            WallpaperGroup.wpg442 -> {
                theCorner = Double2.zero
                theUnscaledTranslations = theSquare
            }

            WallpaperGroup.wpg632 -> {
                theCorner = Double2.zero
                theUnscaledTranslations = theRhombus6
            }

            WallpaperGroup.wpgS2222 -> {
                theCorner = Double2(0.25, 0.0)
                theUnscaledTranslations = theSquare
            }

            WallpaperGroup.wpgS333 -> {
                theCorner = Double2.zero
                theUnscaledTranslations = theRhombus6
            }

            WallpaperGroup.wpgS442 -> {
                theCorner = Double2.zero
                theUnscaledTranslations = theSquare
            }

            WallpaperGroup.wpgS632 -> {
                theCorner = Double2.zero
                theUnscaledTranslations = theRhombus6
            }

            WallpaperGroup.wpg22S -> {
                theCorner = Double2.zero
                theUnscaledTranslations = theSquare
            }

            WallpaperGroup.wpg2S22 -> {
                theCorner = Double2(0.5, 0.0)
                theUnscaledTranslations =
                    Double2x2(
                        Double2(1.0, -1.0),
                        Double2(1.0, +1.0),
                    )
            }

            WallpaperGroup.wpg3S3 -> {
                theCorner = Double2.zero
                theUnscaledTranslations = theRhombus6
            }

            WallpaperGroup.wpg4S2 -> {
                theCorner = Double2.zero
                theUnscaledTranslations = theSquare
            }

            WallpaperGroup.wpgSS -> {
                theCorner = Double2.zero
                theUnscaledTranslations = theSquare
            }

            WallpaperGroup.wpg22X -> {
                theCorner = Double2(0.0, 0.25)
                theUnscaledTranslations = theSquare
            }

            WallpaperGroup.wpgSX -> {
                theCorner = Double2.zero
                theUnscaledTranslations =
                    Double2x2(
                        Double2(1.0, -1.0),
                        Double2(1.0, +1.0),
                    )
            }

            WallpaperGroup.wpgXX -> {
                theCorner = Double2.zero
                theUnscaledTranslations = theSquare
            }
        }

        //	Rescale the translations so that the unit cell
        //	has the desired area.
        val theRawUnitCellArea = theUnscaledTranslations.determinant // 	known to be > 0.0
        var theDesiredUnitCellArea = 0.25 * 0.25 // 	also > 0.0
        if (wallpaperGroup == WallpaperGroup.wpgSX) {

            //	In order to get the group *× to have the same spacing
            //	between the mirror and/or glide reflection lines
            //	as ** and ××, and also to have the same aspect ratio,
            //	we need *× to have twice the default area.
            theDesiredUnitCellArea *= 2.0
        }
        if (wallpaperGroup == WallpaperGroup.wpg2S22) {

            //	In order to get the group 2*22 to have the same spacing
            //	between the mirror and/or glide reflection lines
            //	as *2222, **, *×, ××, 22* and 22×, the same spacing
            //	between 2-fold gyration points as 2222,
            //	and also to have the same aspect ratio,
            //	we need 2*22 to have twice the default area.
            theDesiredUnitCellArea *= 0.5
        }
        val theScaleFactor = sqrt(theDesiredUnitCellArea / theRawUnitCellArea) // => safe

        itsCorner = theCorner * theScaleFactor
        itsTranslationsStorage = theUnscaledTranslations * theScaleFactor
        //	Port note:  written to the storage directly because,
        //	as in Swift, initialization doesn't run the didSet observer.

        //	Set a dummy metric so that this UnitCellPlacement
        //	will be "fully initialized" and then...
        itsMetricOfDet1 = Double2x2.identity

        //	...immediately replace the dummy value
        //	with the metric that corresponds to itsTranslations.
        recomputeMetric()
    }

    //	Port note:  see the note at the top of this class.
    fun copy(): UnitCellPlacement {
        val theCopy = UnitCellPlacement(defaultForWallpaperGroup = WallpaperGroup.wpgO)
        theCopy.itsCorner = itsCorner
        theCopy.itsTranslations = itsTranslations // 	recomputes the metric
        return theCopy
    }

    // MARK: -
    // MARK: Metric

    private fun recomputeMetric() {

        if (unitCellIsDegenerate()) {
            itsMetricOfDet1 = Double2x2.identity
            return
        }

        //	itsTranslations define a mapping from extended unit cell coordinates
        //	to drawing coordinates.  Isotropically rescale the mapping to be area-preserving.
        //	Algebraically, this means rescale it to have determinant 1.
        //	In effect this will map the unit cell to a unit-area parallelogram
        //	of the required shape.

        //	The check for UnitCellIsNondegenerate() should ensure
        //	that the determinant is never too close to zero.
        val theFactor = 1.0 / sqrt(fabs(itsTranslations.determinant))
        val theRescaledTranslations = theFactor * itsTranslations

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

    fun unitCellIsDegenerate(): Boolean {

        //	Unit cell non-degeneracy constraints
        val theMinSideLength = 0.015625 // 	2⁻⁶,  in drawing units
        val theMaxSideLength = 64.0 // 	2⁺⁶,  in drawing units
        val theMaxSideRatio = 8.0 // 	For rhombic groups,
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
        val theMinSine = 0.1 // 	had been 0.5 in legacy version

        //	Note the lengths of the two translation vectors.
        val theLengths = listOf(length(itsTranslations[0]), length(itsTranslations[1]))

        //	Make sure each translation vector is neither too long nor too short.
        for (theLength in theLengths) {
            if (theLength < theMinSideLength || theLength > theMaxSideLength) {
                return true
            }
        }

        //	Make sure the ratio of the two translation lengths
        //	isn't too great or too small.
        if (
            theLengths[0] > theMaxSideRatio * theLengths[1] ||
                theLengths[1] > theMaxSideRatio * theLengths[0]
        ) {
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
        val theUnitVectors =
            Double2x2(
                itsTranslations[0] / theLengths[0], // 	theLengths[0] ≥ theMinSideLength > 0.0
                itsTranslations[1] / theLengths[1], // 	theLengths[1] ≥ theMinSideLength > 0.0
            )
        val theSine = theUnitVectors.determinant
        if (theSine < theMinSine) {
            return true
        }

        return false
    }

    // MARK: -
    // MARK: Transformations

    fun snapToViewAlignment() {

        //	Sine of the largest rotation angle that
        //	the snap-to-view feature will snap to zero.
        //
        //	0.02 is very subtle but usable.
        //
        //	0.04 makes snapping easier, but could conceivably
        //	     annoy people who want a slightly tilted drawing
        //	     for artistic reasons.
        //
        val theSnapToViewEpsilon = 0.04

        val theTranslations: MutableList<Double2> = mutableListOf()

        theTranslations.add(normalize(itsTranslations[0]))
        theTranslations.add(normalize(itsTranslations[1]))
        theTranslations.add(normalize(itsTranslations[1] - itsTranslations[0]))

        //	Consider each vector rotated by π/2.  That way we need
        //	to compare only to the horizontal, not to the vertical.
        //	In square and hexagonal lattices, the resulting
        //	six translations include all mirror lines.

        val theQuarterTurn =
            Double2x2(
                Double2(0.0, 1.0),
                Double2(-1.0, 0.0),
            )

        theTranslations.add(theQuarterTurn * theTranslations[0]) // 	right-to-left action
        theTranslations.add(theQuarterTurn * theTranslations[1]) // 	right-to-left action
        theTranslations.add(theQuarterTurn * theTranslations[2]) // 	right-to-left action

        for (theTranslation in theTranslations) {

            //	Negate theTranslation if necessary so that
            //	its x-component will be non-negative.
            val thePosTranslation =
                (if (theTranslation[0] >= 0.0) theTranslation else -theTranslation)

            //	thePosTranslation almost aligns with the horizontal
            //	iff the sine of its angle is small.  Because the vector
            //	is normalized, the sine is simply theTranslation[1].
            if (fabs(thePosTranslation[1]) < theSnapToViewEpsilon) {

                //	Note the cosine and sine of the required rotation.
                val cosθ = thePosTranslation[0]
                val sinθ = -thePosTranslation[1]

                val theRotation =
                    Double2x2(
                        Double2(cosθ, sinθ),
                        Double2(-sinθ, cosθ),
                    )

                //	Rotate both unit cell translation vectors.
                itsTranslations =
                    itsTranslations.withColumn(
                        0,
                        theRotation * itsTranslations[0],
                    ) //	right-to-left action
                itsTranslations =
                    itsTranslations.withColumn(
                        1,
                        theRotation * itsTranslations[1],
                    ) //	right-to-left action

                //	We can snap to at most one direction, so we're done.
                //	(And because we've changed itsTranslations,
                //	the theTranslations are no longer valid in any case.)
                //
                return
            }
        }
    }

    fun transform(using: Double3x2) { // 	the last column of the 3×3 matrix
        //	(using left-to-right matrix actions)
        //	isn't explicitly included, because
        //	implicitly it's always (0,0,1)
        val transformation = using

        itsCorner =
            (transformation //	right-to-left matrix action
            * Double3(itsCorner, 1.0))

        //	itsTranslations[i] is a "horizontal" vector (x,y,0).
        //	In effect it's the difference of two points,
        //	so it responds to tbe transformation's dilational/rotational part,
        //	but not to its translational part.

        itsTranslations =
            itsTranslations.withColumn(
                0,
                transformation //	right-to-left matrix action
                * Double3(itsTranslations[0], 0.0),
            )

        itsTranslations =
            itsTranslations.withColumn(
                1,
                transformation //	right-to-left matrix action
                * Double3(itsTranslations[1], 0.0),
            )
    }

    fun centerTheUnitCell() {

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
            "non-positive determinant",
        )

        val theDrawingOriginInUnitCellCoordinates = (itsTranslations.inverse * -itsCorner)

        //	The floor of each of the view-origin's unit cell coordinates
        //	tells us by what integer multiple of each unit cell translation vector
        //	we need to shift the unit cell's origin.
        //	(Draw a picture and this will be clear!)
        //	If both of the origin's unit cell coordinates have floor 0,
        //	then we don't need to shift the cell origin at all.

        val theMultiples = floor(theDrawingOriginInUnitCellCoordinates)

        itsCorner += itsTranslations * theMultiples // 	right-to-left matrix action
    }
}

data class UnitCellShape(

    //	itsAspectRatio = itsTranslations[1]
    //				   / itsTranslations[0]
    //
    var aspectRatio: Double,

    //	When the unit cell is a rectangle,
    //	itsTranslations[1] is orthogonal to itsTranslations[0].
    //	To create a generic parallelogram, we may add a multiple
    //	of itsTranslations[0] to itsTranslations[1], like this
    //
    //		itsTranslations[1] += shear * itsTranslations[0]
    //
    var shear: Double,
)
