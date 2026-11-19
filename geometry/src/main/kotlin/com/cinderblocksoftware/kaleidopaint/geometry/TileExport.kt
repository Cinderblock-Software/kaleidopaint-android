// Ported from KaleidoPaintDocument.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.max
import kotlin.math.min

fun KaleidoPaintDocument.prepareModelToExportTileableRectangle(
    availableWidthPx: Int,
    availableHeightPx: Int,
): Pair<Int, Int> { // 	(specialWidthPx, specialHeightPx)

    //	Prepare to render a (typically tileable) rectangle.
    //
    //	For a group other than ○ or 2222,
    //		save a rectangle that tiles "straight across".
    //
    //	For ○ or 2222,
    //		the unit cell can be a generic parallelogram,
    //		so the best we can do is to save a rectangle
    //		that tiles straight across horizontally
    //		but tiles vertically with an offset.
    //

    //	We'll need to temporarily adjust itsUnitCellPlacement
    //	to let the unit cell fill the frame.
    //	so let's first save the current unit cell placement,
    //	so that restoreModelAfterExportingTileableRectangle()
    //	may restore it afterwards.
    //
    itsRestorableUnitCellPlacement = itsUnitCellPlacement.copy()

    //	Our task now is to change the UnitCellPlacement so that
    //	exactly one copy of the unit cell will appear (for rectangular groups)
    //	or exactly two copies (for rhombic groups).

    val theShapeConstraints = itsWallpaperGroup.torusGroup.itsUnitCellShapeConstraints
    val theUnitCellTranslations = itsUnitCellPlacement.itsTranslations

    val theRawRectTranslations: Double2x2 // 	in drawing coordinates
    val theRawSkew: Double

    if (theShapeConstraints.contains(ShapeConstraint.angle_2π_over_4)) {

        //	The group is rectangular.

        //	The unit cell may be exported as is.
        theRawRectTranslations = theUnitCellTranslations

        //	The unit cell is rectangular, so no skew.
        theRawSkew = 0.0
    } else if (theShapeConstraints.contains(ShapeConstraint.rhombus)) {

        //	The group is rhombic (but not square).
        //	It may be a triangular or hexagonal group,
        //	or it may be a group with mirror lines
        //	and/or glide reflections.

        //	The tileable rectangle's horizontal translation
        //	will be the sum of the rhomb's translations, while
        //	the tileable rectangle's vertical translation
        //	will be the difference of the rhomb's translations.
        //
        theRawRectTranslations =
            Double2x2(
                theUnitCellTranslations[0] + theUnitCellTranslations[1],
                theUnitCellTranslations[1] - theUnitCellTranslations[0],
            )

        //	The unit cell is rhombic, so no skew.
        theRawSkew = 0.0
    } else {

        //	The group is either ○ or 2222.
        //	The unit cell may be any parallelogram.
        //
        //		Note:  I might someday write some code to look
        //		for an approximate rectangle in a generic lattice,
        //		which, after tweaking the unit cell to make
        //		the approximate rectangle an exact rectangle,
        //		which could be saved as a tileable image.
        //		But I don't have time to pursue that now,
        //		because more pressing projects sit higher up
        //		on my job queue.
        //
        //	One might consider trying to export the true unit cell,
        //	which is a parallelogram:
        //
        //			      +--------+
        //			     /        /
        //			    /        /
        //			   /        /
        //			  /        /
        //			 /        /
        //			+--------+
        //
        //	but some technical obstacles stand in the way, namely:
        //
        //	(1) We'd need to fill the triangular regions outside
        //		the parallelogram with transparency, but Photoshop
        //		has a bug that when people downsample an image,
        //		Photoshop screws up the pixels along border
        //		iff the image has an alpha channel.
        //
        //	(2) Working with the parallelogram might be less convenient
        //		for users in any case, even though it would convey
        //		the geometrical meaning most clearly.
        //
        //	So instead let's export a rectangle whose content
        //	is the same as that of the parallelogram:
        //
        //			+-----+--+-----+
        //			|    /   |    /
        //			|   /    |   /
        //			|  /     |  /
        //			| /      | /
        //			|/       |/
        //			+--------+
        //
        //	Such a rectangle will tile straight across in the horizontal direction
        //	but when tiling in the vertical direction will require an offset
        //	to get the content to match up.  We'll take care to ensure that
        //	the required offset be an integer number of pixels.

        //	itsTranslations should never be degenerate, but check anyhow.
        val theLength0 = length(theUnitCellTranslations[0])
        if (theLength0 == 0.0) {
            assertionFailure("Internal error:  itsTranslations[0] has length zero")
            return Pair(availableWidthPx, availableHeightPx)
        }

        //	Split itsTranslations[1] into a component parallel to itsTranslations[0]
        //	and a component perpendicular to itsTranslations[0].
        val theUnitVector0 = theUnitCellTranslations[0] / theLength0
        val theParallelComponentLength =
            (theUnitCellTranslations[1].x * theUnitVector0.x +
                theUnitCellTranslations[1].y * theUnitVector0.y)
        val theParallelComponent = theParallelComponentLength * theUnitVector0
        val thePerpendicularComponent = theUnitCellTranslations[1] - theParallelComponent

        //	The exported rectangle's horizontal side matches the base of the parallelogram.
        //	The vertical side is the vertical line shown in the diagram above.
        theRawRectTranslations =
            Double2x2(
                theUnitCellTranslations[0],
                thePerpendicularComponent,
            )

        //	Note how skewed the unit cell is.
        theRawSkew = theParallelComponentLength
    }

    val theRawRectWidth = length(theRawRectTranslations[0])
    val theRawRectHeight = length(theRawRectTranslations[1])

    //	Find the largest rectangle (in pixels) that
    //	doesn't exceed the proposed size.
    //
    //		Note:  In practice
    //
    //			availableWidthPx == availableHeightPx
    //
    //		but we don't rely on that fact.
    //
    //	Which dimension (width or height) is more crowded?
    //	Conceptually we want to check whether
    //
    //		theRawRectWidth     theRawRectHeight
    //		---------------- >? -----------------
    //		availableWidthPx    availableHeightPx
    //
    //	but computationally it's more efficient to check
    //
    //		theRawRectWidth * availableHeightPx
    //	 >?
    //		theRawRectHeight * availableWidthPx
    //
    var theRectWidthPx: Int
    var theRectHeightPx: Int
    if (
        theRawRectWidth * availableHeightPx.toDouble() >
            theRawRectHeight * availableWidthPx.toDouble()
    ) {

        //	The width is more crowded.
        theRectWidthPx = availableWidthPx
        theRectHeightPx =
            round((theRawRectHeight / theRawRectWidth) * theRectWidthPx.toDouble()).toInt()

        //	Just to be safe, clamp theRectHeightPx to the range [1, availableHeightPx].
        theRectHeightPx = max(1, min(availableHeightPx, theRectHeightPx))
    } else {

        //	The height is more crowded.
        theRectHeightPx = availableHeightPx
        theRectWidthPx =
            round((theRawRectWidth / theRawRectHeight) * theRectHeightPx.toDouble()).toInt()

        //	Just to be safe, clamp theRectWidthPx to the range [1, availableWidthPx].
        theRectWidthPx = max(1, min(availableWidthPx, theRectWidthPx))
    }

    //	The theRawRectTranslations have approximately the same aspect ratio
    //	as the integer-valued (theRectWidthPx, theRectHeightPx).
    //	Replace them with translations that have exactly
    //	the same aspect ratio, namely
    //
    //			(theRectWidthPx,       0        )
    //			(      0,        theRectHeightPx)
    //
    //	The scale isn't important at this point -- we'll deal with it momentarily.
    //
    //	Also replace theRawSkew with a value that corresponds to an integer number of pixels,
    //	so that the exported images may be tiled exactly.
    val theSkewPx = round(theRectWidthPx.toDouble() * (theRawSkew / theRawRectWidth))

    //	As explained in the extended comment on "Coordinate systems"
    //	in KaleidoPaintCoordinateSystems.swift, the image's diagonal
    //	has length exactly 1.0 in drawing coordinates, by definition.
    val theDrawingUnitsPerPixel =
        1.0 / kotlin.math.hypot(theRectWidthPx.toDouble(), theRectHeightPx.toDouble())

    //	Scale the translations (defined in the comment above) and theSkewPx
    //	so that the rectangle exactly fills the image.
    val theScaledWidth = theDrawingUnitsPerPixel * theRectWidthPx.toDouble()
    val theScaledHeight = theDrawingUnitsPerPixel * theRectHeightPx.toDouble()
    val theScaledSkew = theDrawingUnitsPerPixel * theSkewPx

    //	Set itsUnitCellPlacement's translations to fit theRectTranslations and theSkew.
    if (theShapeConstraints.contains(ShapeConstraint.angle_2π_over_4)) {

        //	The group is rectangular.

        itsUnitCellPlacement.itsTranslations =
            Double2x2(
                Double2(theScaledWidth, 0.0),
                Double2(0.0, theScaledHeight),
            )
    } else if (theShapeConstraints.contains(ShapeConstraint.rhombus)) {

        //	The group is rhombic (but not square).
        //	It may be a triangular or hexagonal group,
        //	or it may be a group with mirror lines
        //	and/or glide reflections.

        itsUnitCellPlacement.itsTranslations =
            Double2x2(
                Double2(
                    0.5 * theScaledWidth,
                    -0.5 * theScaledHeight,
                ),
                Double2(
                    0.5 * theScaledWidth,
                    +0.5 * theScaledHeight,
                ),
            )
    } else {

        //	The group is either ○ or 2222.
        //	The unit cell may be any parallelogram.

        itsUnitCellPlacement.itsTranslations =
            Double2x2(
                Double2(theScaledWidth, 0.0),
                Double2(theScaledSkew, theScaledHeight),
            )
    }

    //	We can place itsUnitCellPlacement's corner wherever it looks good,
    //	for example at the image's lower-left corner.
    itsUnitCellPlacement.itsCorner =
        Double2(
            -0.5 * theScaledWidth,
            -0.5 * theScaledHeight,
        )

    //	Note:  We've changed the unit cell's placement but not its shape,
    //	so there's no need to redraw the unit cell textures.

    //	Let the caller know how big to make the image.
    return Pair(theRectWidthPx, theRectHeightPx)
}

fun KaleidoPaintDocument.restoreModelAfterExportingTileableRectangle() {

    //	Undo the action of prepareModelToExportTileableRectangle().

    val theRestorableUnitCellPlacement =
        itsRestorableUnitCellPlacement
            ?: run {
                assertionFailure(
                    "Internal error:  itsRestorableUnitCellPlacement is unexpectedly nil"
                )
                return
            }

    itsUnitCellPlacement = theRestorableUnitCellPlacement
    itsRestorableUnitCellPlacement = null

    //	Note:  We've changed the unit cell's placement but not its shape,
    //	so there's no need to redraw the unit cell textures.
}
