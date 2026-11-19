// Ported from KaleidoPaintDocument.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

@file:Suppress("ClassName", "LocalVariableName", "PropertyName")

package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.sqrt

//	Port note:  This is KaleidoPaintDocument.swift without the SwiftUI
//	document plumbing. The tileable-rectangle helpers live in TileExport.kt.
//	The plumbing
//	(ReferenceFileDocument, snapshot(), fileWrapper()) has no counterpart here:
//	the app module opens and saves files and calls decodeFileFormat()
//	and encodeFileFormat().

enum class TouchMode {

    draw,
    edit;

    val id: TouchMode
        get() = this

    //	For SwiftUI this should really return a LocalizedStringKey,
    //	but non-SwiftUI code doesn't know about LocalizedStringKeys
    //	so we return a plain String and let the caller convert it as needed.
    fun localizedNameKey(): String {
        return when (this) {
            draw -> "DrawMode" // 	translates as "Draw"
            edit -> "EditMode" // 	translates as "Edit"
        }
    }
}

//	Default dot and curve thickness
//
//	gDefaultThickness is the default value for the group ○.
//	When a new drawing is created for any other group,
//	the initial thickness is set to gDefaultThickness divided by
//	the order of the torus group.  The torus group may have order
//	up to 12, as occurs for *632, in which case the initial thickness
//	is gDefaultThickness/sqrt(12).  However, if the user changes
//	the group after the drawing is created, the thickness doesn't change.
//
const val gDefaultThickness = 0.03125 // 	in unit cell coordinates

//	The current version of KaleidoPaint uses a fixed unit cell resolution
//	of 11, which strikes a good balance between image quality and speed.
//
//		2¹¹ × 2¹¹ = 2048 × 2048 pixels
//
const val log2UnitCellResolution: Int = 11

/**
 * UI-owned mutable model. Writers hold its monitor; GL renders a RenderSnapshot. Background saves
 * encode a detached snapshot; GL publishes only validated fill caches.
 */
class KaleidoPaintDocument(

    //	Port note:  The Swift original reads the group that new drawings
    //	start in from UserDefaults ("default symmetry group").
    //	Here whoever creates the document passes it in.
    defaultSymmetryGroup: WallpaperGroup = WallpaperGroup.wpgO
) {

    // MARK: -
    // MARK: Model data

    //	Note that GeometryGamesUpdatable.changeCount has nothing to do
    //	with saving changes; SwiftUI saves changes iff there are items
    //	on the undo stack.

    var itsWallpaperGroup: WallpaperGroup = defaultSymmetryGroup

    var itsUnitCellPlacement: UnitCellPlacement =
        UnitCellPlacement(defaultForWallpaperGroup = defaultSymmetryGroup)

    fun mutateUnitCellPlacement(
        corner: Double2,
        translationsMultiplier: Double,
    ) {
        //	KaleidoPaintThumbnailProvider, which is nonisolated
        //	to match its superclass KaleidoPaintThumbnailProvider,
        //	needs an isolated method to call to mutate itsUnitCellPlacement.
        //	It can't mutate them directly.

        itsUnitCellPlacement.itsCorner = corner
        itsUnitCellPlacement.itsTranslations *= translationsMultiplier
    }

    //	When the user chooses Save Tileable Rectangle,
    //	we'll need to temporarily adjust itsUnitCellPlacement
    //	to properly place the unit cell.  Afterwards we'll
    //	restore itsUnitCellPlacement to its previous value,
    //	which we store here.  This variable is used only
    //	while saving a tileable rectangle.  At all other times
    //	it's set to nil.
    var itsRestorableUnitCellPlacement: UnitCellPlacement? = null

    //	Note:  If you copy colors from the SwiftUI ColorPicker,
    //	you must gamma-decode their components, like this
    //
    //		LinearDisplayP3Color(
    //			r: gammaDecode(128.0/255.0),
    //			g: gammaDecode(  0.0/255.0),
    //			b: gammaDecode(192.0/255.0),
    //			a: 1.0)
    //

    //	What color should newly created dots and curves have?
    var itsBrushColor: LinearDisplayP3Color =
        LinearDisplayP3Color(r = 1.00, g = 0.00, b = 0.00, a = 1.0)

    //	What color should newly created flood fills have?
    var itsFillColor: LinearDisplayP3Color =
        LinearDisplayP3Color(r = 0.25, g = 0.00, b = 1.00, a = 1.0)

    //	What color should the background have?
    var itsBackgroundColor: LinearDisplayP3Color =
        LinearDisplayP3Color(r = 0.37636709, g = 0.75232202, b = 0.95496619, a = 1.0)

    //	What thickness should newly created dots and curves have?
    //
    //		Note:  On the one hand, we set a default brush thickness
    //		that's proportional to the quotient orbifold's linear dimensions.
    //		On the other hand, if the user later changes the wallpaper group,
    //		we keep the same brush thickness — we don't rescale it
    //		for the new group.
    //
    var itsBrushThickness: Double = // 	in unit cell coordinates
        gDefaultThickness / sqrt(defaultSymmetryGroup.torusGroup.itsElements.size.toDouble())

    //	How vigorously should KaleidoPaint smooth newly created curves,
    //	to eliminate any untentional little wobbles that the user's
    //	shaky finger might have produced?
    //
    //		The comments in ramerDouglasPeucker() and
    //		ramerDouglasPeuckerInteriorNodes() explain
    //		itsSmoothingTolerance's geometrical significance.
    //
    var itsSmoothingTolerance: Double = 0.0085 // 	medium

    //	Show mirror lines, gyration points and glide axes?
    var itsShowSingularitiesFlag: Boolean = true

    //	When color-by-symmetry is enabled, KaleidoPaint
    //	ignores user-assigned colors and instead assigns colors
    //	based on how each copy of the motif is rotated and/or reflected
    //	relative to the base copy.  In other words,
    //	two copies of a motif get assigned the same color
    //	if and only if they differ by a pure translation.
    //	In group-theoretic terms, the color-by-symmetry feature
    //	colors the cosets of the translation subgroup H
    //	in the full symmetry group G (see the comment
    //	on "Unit cells" in KaleidoPaintWallpaperGroup.swift
    //	for more details on the group-theoretic aspects).
    var itsColorBySymmetryFlag: Boolean = false

    //	The user may lock the drawing's content to prevent accidental changes.
    var itsContentIsLocked: Boolean = false

    var itsElements: MutableList<DrawingElement> = mutableListOf()

    //	When the user taps a control handle in TouchToEdit mode,
    //	remember the selected control point along with some other
    //	useful information about the hit.  itsControlHandleHit
    //	will be non-nil only while a drag is in progress or,
    //	in the case that the user taps a control point,
    //	while the requested popup menu is visible.
    //	Beyond that, there is no notion of a selected element.
    var itsControlHandleHit: ControlHandleHit? = null

    //	It would be tempting to simply set flag like
    //
    //		var itsBaseDrawingTextureNeedsFullRedraw: Bool = true
    //
    //	to let the renderer know when a texture needs a redraw.
    //	Unfortunately that approach ran afoul of a bug that was
    //	present in certain versions of iOS. The problem was that
    //	when SwiftUI creates the KaleidoPaintContentView,
    //	it was creating two copies of its @State variables and
    //	also two copies of the GeometryGamesView. It was installing
    //	both copies of the GeometryGamesView into the window and
    //	calling encodeCommands() to both. Aside from the obvious
    //	wasted effort, this was also preventing the visible
    //	GeometryGamesView from getting drawn correctly, because
    //	its invisible twin was clearing the flags for
    //	itsBaseDrawingTextureNeedsFullRedraw, etc.  Ugh.
    //
    //	To avoid that bug (and for greater robustness in general)
    //	I've replaced the boolean redraw flags with integer
    //	redraw request counts. The renderer (or each renderer
    //	if there's more than one!) will know to redraw a texture
    //	whenever the count is greater than the last count that
    //	it redrew the texture for.
    //
    //	Historical note:
    //
    //		KaleidoPaint worked fine up through iOS 18.0.
    //		Then as soon as iOS 18.1 came out, the graphics view
    //		started showing only pure black. I recompiled
    //		the exact same v3.0.5 KaleidoPaint source code
    //		using the new version of Xcode and then everying worked
    //		fine again, so I released the result as KaleidoPaint 3.0.6.
    //		Same source code, just a recompile. Almost surely
    //		that black screen was a result of the bug described
    //		in the preceding paragraphs.
    //
    //		The bug re-appeared in iOS 18.4, which is where
    //		I first discovered that it was creating two copies
    //		of the GeometryGamesView, which caused the black-screen
    //		problem described above along with a memory leak:
    //			init GeometryGamesView
    //			init GeometryGamesView
    //			deinit GeometryGamesView
    //
    //		Fortunately iOS 18.5 creates only one copy of
    //		the GeometryGamesView, avoiding any risk of the
    //		black-screen problem and avoiding the memory leak:
    //			init GeometryGamesView
    //			deinit GeometryGamesView
    //
    //		I'm not sure how deterministic those behaviors were.
    //		There might have been race conditions in play,
    //		and indeed it's conceivable that there are still
    //		potential race conditions in the current version of iOS,
    //		even if the bug is no longer manifesting itself.
    //
    //		When running the same SwiftUI code on macOS,
    //		SwiftUI creates only one copy of the @State variables
    //		and the GeometryGamesView and everything works fine.
    //		But again, we could just be on the lucky side
    //		of some race conditions deep within SwiftUI.
    //

    //	Set flags to request that the unit cell textures be updated.
    var itsBaseDrawingTextureFullRedrawRequestCount: Int = 1 // 	request initial redraw
    var itsBaseDrawingTextureLastElementRequestCount: Int = 0
    var itsCurveInProgressTextureRedrawRequestCount: Int = 1 // 	request initial redraw
    var itsSingularitiesTextureRedrawRequestCount: Int = 1 // 	request initial redraw
    var itsCompositeTextureRedrawRequestCount: Int = 1 // 	request initial redraw

    //	While the user is drawing a new curve,
    //	we'll keep track of it separately from the rest
    //	of the drawing, and render it in its own texture
    //	(in effect in its own layer) so that we don't
    //	have to re-render the rest of the drawing for every frame.
    var itsCurveInProgress: Curve? = null // 	= NULL when no curve is in progress

    //	The points comprising a curve-in-progress will
    //	arrive in extended unit cell coordinates and get mapped
    //	to regular unit cell coordinates.  For example, a point
    //	that arrives as (-3.2, 4.5) might get mapped to (0.8, 0.5).
    //	A complication arises when, say, a series of points
    //	(18.6, 7.5 + 0.1n) arrives, for n=0…20.
    //	The first point (18.6, 7.5) maps to (0.6, 0.5) no problem.
    //	but by the time we reach (18.6, 9.0) we've got a problem
    //	because, by continuity, we're mapping it to (0.6, 2.0),
    //	which lies outside the "padded safe region"
    //	defined in KaleidoPaintWallpaperGroup.swift.
    //	The solution is to modify our basepoint, so (18.6, 7.5 + 0.1n)
    //	maps not to (0.6, 0.5 + 0.1n), but to (0.6, -0.5 + 0.1n).
    //
    //	When the first point arrives, we don't yet know which
    //	basepoint will be best, so we consider all nine possibilities.
    //	For example, if we receive a first point (18.6, 7.5),
    //	we'd consider potential basepoints {17, 18, 19} × {6, 7, 8}.
    //	For each of the nine potential basepoints, we keep a flag
    //	saying whether it's compatible with all points received so far,
    //	in the sense that it maps all points into the padded safe region.
    //	If we receive a point that would invalidate the last valid basepoint,
    //	we reject that point and all subsequent points received as part
    //	of that curve.  This policy not only ensures that all curves
    //	will get drawn correctly and efficiently, but it also offers
    //	the aesthetic bonus that users may not draw a single curve
    //	spanning tens of copies of the fundamental cell.  In the older
    //	version of KaleidoPaint, new users often did that unintentionally
    //	when first learning to use the app, and the result was almost
    //	always ugly.
    var itsCurveInProgressTouchOffset: Int2 = Int2.zero // 	(-18,-7) in the example above
    var itsCurveInProgressValidBasepoints: MutableSet<Int2> = mutableSetOf()
    var itsCurveInProgressAcceptsNewPoints: Boolean = false

    //	Undo and Redo are an integral part of making a drawing
    //	in KaleidoPaint, so KaleidoPaint provides convenient
    //	(and obvious!) Undo and Redo buttons at the top of the scene
    //	(as opposed to insisting on that the user do
    //	a 3-finger swipe left/right to undo/redo, or a 3-finger tap
    //	to access iOS's built-in Undo|Cut|Copy|Paste|Redo bar).
    //
    //	Unfortunately
    //
    //		"UndoManager.canUndo is not KVO compliant"
    //
    //	as explained on the web page
    //
    //
    //	https://stackoverflow.com/questions/60647857/undomanagers-canundo-property-not-updating-in-swiftui
    //
    //	A comment on that same page goes on to say why
    //	listening for an NSUndoManagerCheckpoint notification
    //	won't work either, because it generates an infinite recursion
    //	when checking the redo state.
    //
    //	So to keep the code straightforward and robust,
    //	let's keep a variable itsUndoRedoCount that we update
    //	whenever we modify the Undo/Redo stack, so that our
    //	Undo and Redo buttons will get enabled or disabled appropriately.
    //
    var itsUndoManager: UndoManager? = null // 	KaleidoPaintContentView's body() will set this.
    var itsUndoRedoCount: Int = 0

    var itsTouchMode: TouchMode = TouchMode.draw

    //	Port note:  Where the Swift original writes the user's choice of group
    //	to UserDefaults ("default symmetry group"), to be the group that
    //	the next new drawing starts in, this calls whoever wants to know.
    var itsDefaultSymmetryGroupObserver: ((WallpaperGroup) -> Unit)? = null

    // MARK: -
    // MARK: File encoding

    sealed class KaleidoPaintFileEncodingError(val reason: String) : Exception(reason) {
        class fileFormatError(reason: String) : KaleidoPaintFileEncodingError(reason)
    }

    val theCurrentMajorVersionNumber = 1
    val theCurrentMinorVersionNumber = 10

    fun encodeFileFormat(): String {

        val theDrawingAsText = StringBuilder()

        theDrawingAsText.append("KaleidoPaint Drawing\n")
        theDrawingAsText.append(
            stringWithFormat(
                "format %d.%d\n",
                theCurrentMajorVersionNumber,
                theCurrentMinorVersionNumber,
            )
        )
        theDrawingAsText.append("\n")

        theDrawingAsText.append("wallpaper group " + itsWallpaperGroup.rawValue + "\n")

        theDrawingAsText.append(
            stringWithFormat(
                "unit cell placement\n\t%20.16lf %20.16lf\n\t%20.16lf %20.16lf\n\t%20.16lf %20.16lf\n",
                itsUnitCellPlacement.itsCorner[0],
                itsUnitCellPlacement.itsCorner[1],
                itsUnitCellPlacement.itsTranslations[0][0],
                itsUnitCellPlacement.itsTranslations[0][1],
                itsUnitCellPlacement.itsTranslations[1][0],
                itsUnitCellPlacement.itsTranslations[1][1],
            )
        )

        //	We could define a new version of the KaleidoPaint file format
        //	that omits the log2 unit cell resolution, but changing
        //	file formats is a pain and it's not out of the question
        //	that we'd someday want to support a larger resolution.
        //	So let's leave the file format as it is, and simply
        //	write the current fixed resolution (11) into the file.
        theDrawingAsText.append(
            stringWithFormat(
                "log2 unit cell resolution %d\n",
                11,
            )
        )

        theDrawingAsText.append(
            stringWithFormat(
                "background color %12.8f %12.8f %12.8f %12.8f\n",
                itsBackgroundColor.r,
                itsBackgroundColor.g,
                itsBackgroundColor.b,
                itsBackgroundColor.a,
            )
        ) //	= 1.0

        theDrawingAsText.append(
            stringWithFormat(
                "brush color      %12.8f %12.8f %12.8f %12.8f\n",
                itsBrushColor.r,
                itsBrushColor.g,
                itsBrushColor.b,
                itsBrushColor.a,
            )
        ) //	= 1.0

        theDrawingAsText.append(
            stringWithFormat(
                "fill color       %12.8f %12.8f %12.8f %12.8f\n",
                itsFillColor.r,
                itsFillColor.g,
                itsFillColor.b,
                itsFillColor.a,
            )
        ) //	= 1.0

        theDrawingAsText.append(
            stringWithFormat(
                "brush thickness  %20.16lf\n",
                itsBrushThickness,
            )
        )

        theDrawingAsText.append(
            stringWithFormat(
                "smoothing tolerance  %20.16lf\n",
                itsSmoothingTolerance,
            )
        )

        theDrawingAsText.append(
            "show singularities " + (if (itsShowSingularitiesFlag) "true" else "false") + "\n"
        )

        theDrawingAsText.append(
            "color by symmetry  " + (if (itsColorBySymmetryFlag) "true" else "false") + "\n"
        )

        theDrawingAsText.append(
            "content is locked  " + (if (itsContentIsLocked) "true" else "false") + "\n"
        )

        theDrawingAsText.append("\n")
        theDrawingAsText.append("elements\n")
        theDrawingAsText.append("\n")

        val theColorFormat = "\tcolor     %12.8f %12.8f %12.8f %12.8f\n"

        for (theElement in itsElements) {

            //	Is theElement a Dot?
            if (theElement is Dot) {
                val theDot = theElement

                theDrawingAsText.append("dot\n")

                theDrawingAsText.append(
                    stringWithFormat(
                        theColorFormat,
                        theDot.itsColor.r,
                        theDot.itsColor.g,
                        theDot.itsColor.b,
                        theDot.itsColor.a,
                    )
                )

                theDrawingAsText.append(
                    stringWithFormat(
                        "\tcenter    %20.16lf %20.16lf\n",
                        theDot.itsCenter[0],
                        theDot.itsCenter[1],
                    )
                )

                theDrawingAsText.append(
                    stringWithFormat(
                        "\tdiameter  %20.16lf\n",
                        theDot.itsThickness,
                    )
                )
            }

            //	Is theElement a Curve?
            if (theElement is Curve) {
                val theCurve = theElement

                theDrawingAsText.append("curve\n")

                theDrawingAsText.append(
                    stringWithFormat(
                        theColorFormat,
                        theCurve.itsColor.r,
                        theCurve.itsColor.g,
                        theCurve.itsColor.b,
                        theCurve.itsColor.a,
                    )
                )

                theDrawingAsText.append(
                    stringWithFormat(
                        "\tthickness %20.16lf\n",
                        theCurve.itsThickness,
                    )
                )

                for (theNode in theCurve.itsSpline.itsNodes) {

                    theDrawingAsText.append(
                        stringWithFormat(
                            "\tnode      %12.8lf %12.8lf   ",
                            theNode.itsNodeLocation[0],
                            theNode.itsNodeLocation[1],
                        ) + theNode.itsNodeType.rawValue + "\n"
                    )
                }
            }

            //	Is theElement a Fill?
            if (theElement is Fill) {
                val theFill = theElement

                theDrawingAsText.append("fill\n")

                theDrawingAsText.append(
                    stringWithFormat(
                        theColorFormat,
                        theFill.itsColor.r,
                        theFill.itsColor.g,
                        theFill.itsColor.b,
                        theFill.itsColor.a,
                    )
                )

                theDrawingAsText.append(
                    stringWithFormat(
                        "\tfillPoint %20.16lf %20.16lf\n",
                        theFill.itsFillPoint[0],
                        theFill.itsFillPoint[1],
                    )
                )
            }

            theDrawingAsText.append("\tno-more-properties\n")
            theDrawingAsText.append("\n")
        }

        theDrawingAsText.append("no-more-elements\n")

        return theDrawingAsText.toString()
    }

    //	Port note:  Where the Swift original would read past the end of its
    //	token array and stop the app (a version number with no dot in it
    //	is the case that can still occur), this reports a file format error
    //	like any other.
    fun decodeFileFormat(drawingAsText: String) {
        try {
            decodeFileFormatWithoutBoundsChecks(drawingAsText)
        } catch (theError: IndexOutOfBoundsException) {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "drawing file is incomplete"
            )
        }
    }

    private fun decodeFileFormatWithoutBoundsChecks(drawingAsText: String) {

        //
        //	Split the drawingAsText String into tokens, separated by white space.
        //
        val theRawTokens = componentsSeparatedByWhitespacesAndNewlines(drawingAsText)
        val t = theRawTokens.filter { it.length > 0 } // 	't' = "tokens"
        val theNumTokens = t.size
        if (theNumTokens < 4) {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "drawing file is impossibly short - fewer than 4 tokens"
            )
        }

        //
        //	Read the file header.
        //

        if (t[0] != "KaleidoPaint" || t[1] != "Drawing" || t[2] != "format") {
            throw KaleidoPaintFileEncodingError.fileFormatError(reason = "invalid header format")
        }

        val theVersionTokens = t[3].split(".").filter { it.isNotEmpty() }
        val theFileFormatMajorVersionNumber =
            swiftInt(theVersionTokens[0])
                ?: throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "unparsable major version number"
                )
        val theFileFormatMinorVersionNumber =
            swiftInt(theVersionTokens[1])
                ?: throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "unparsable minor version number"
                )
        //	We'll need to be more careful with version number validation
        //	if we ever move to format 2.x.  For now, with 1.x only,
        //	the following will do the job.
        //
        // Android accepts only formats it can interpret, including legacy 1.x.
        if (
            theFileFormatMajorVersionNumber != 1L ||
                theFileFormatMinorVersionNumber < 0 ||
                theFileFormatMinorVersionNumber > 10L
        ) {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "Invalid drawing-file format version"
            )
        }

        //	Version 1.1 of the file format stored each color
        //		as a base color of lightness 1/2
        //		along with its actual lightness value.
        //
        //	Version 1.2 and later instead store each color
        //		as a base color of brightness 1
        //		along with its actual brightness value.
        //
        //	Version 1.3
        //
        //		Version 1.2 and earlier used
        //
        //			MTLPixelFormatBGRA8Unorm
        //				which does no gamma-encoding
        //				when writing to the frame buffer
        //
        //		instead of
        //
        //			MTLPixelFormatBGRA8Unorm_sRGB
        //				which automatically gamma-encodes
        //				all R, G and B values (but not alpha values)
        //				that get written to the frame buffer.
        //
        //		Either way, Metal assumes that the values
        //		in the frame buffer are gamma-encoded.
        //		This is a reasonable assumption, given that
        //
        //			the screen can display gamma-encoded color components
        //			directly, in the sense that a voltage of, say,
        //			0.5 times the maximum will produce a brightness
        //			of roughly 0.5^2.2 = 0.22 times the maximum,
        //		and
        //			the sRGB and Display P3 standards both require
        //			the sRGB transfer function (in contrast to GPU shaders
        //			which typically work with linear (not gamma encoded) values).
        //
        //		Because it was using MTLPixelFormatBGRA8Unorm,
        //		Version 1.2 of KaleidoPaint was writing linear RGB values
        //		into the frame buffer, which Metal then interpreted
        //		as gamma-encoded values, thus making mid-tone colors
        //		darker than they should have been.  (In terms of the example
        //		given above, if KaleidoPaint wrote a linear value of 0.5,
        //		Metal would misinterpret it as a gamma-encoded value of 0.5,
        //		which gives ~ 0.22 times the maximum brightness.)
        //
        //		Switching from
        //
        //			MTLPixelFormatBGRA8Unorm
        //
        //		to one of
        //
        //			MTLPixelFormatBGRA8Unorm_sRGB
        //			MTLPixelFormatBGRA10_XR_sRGB
        //			MTLPixelFormatBGR10_XR_sRGB
        //
        //		solved the problem in the sense that KaleidoPaint
        //		now renders colors correctly.  But KaleidoPaint's users
        //		would surely be disappointed to find that all their drawings
        //		have suddenly gotten brighter.  To compensate,
        //		whenever we read a file from Version 1.2 or earlier,
        //		we should gamma-decode all RGB values.
        //		In other words, the difference between Versions 1.2 and 1.3 is that
        //
        //			Version 1.2 accidentally saved what were effectively
        //							gamma-encoded RGB values,
        //		while
        //			Version 1.3 saves linear RGB values.
        //
        //	Version 1.4
        //
        //		Version 1.3 and earlier stored colors in sRGB coordinates.
        //		Version 1.4 stores colors in Display P3 coordinates,
        //		for the reasons explained in definition of a LinearDisplayP3Color.
        //
        //	Version 1.5
        //
        //		Version 1.4 and earlier stored colors
        //		as a base color of brightness 1
        //		along with its actual brightness value.
        //		Version 1.5 no longer factors out the brightness,
        //		but instead stores the color as plain (r,g,b,a).
        //		The opacity value 'a' is always 1.0,
        //		but is nevertheless included for possible future use.
        //
        //	Version 1.6
        //		Version 1.5 and earlier stored the wallpaper group
        //		as an integer index ∈ {0, 1, … , 16}.
        //		Version 1.6 stores the wallpaper group
        //		as a string ∈ {"○", "2222", … , "××"}
        //		containing the group's name in orbifold notation.
        //
        //	Version 1.7
        //		Version 1.7 changes a few of the property names.
        //		Now
        //			Dots have
        //				color
        //				center
        //				diameter  (renames to "itsThickness" in code, but "diameter" in the file)
        //			Curves have
        //				color
        //				thickness
        //				nodes
        //			Fills have
        //				color
        //				fillPoint
        //		KaleidoPaint reads the old names as well as the new ones,
        //		but writes only the new ones.
        //		In addition, the previous version of KaleidoPaint
        //		treated "thickness" as the radius of a dot
        //		or the half-thickness of a curve.
        //		Version 1.7 doubles the old values, so they now represent
        //		the diameter or a dot or the full thickness of a curve.
        //
        //	Version 1.8
        //		Version 1.8 adds the "smoothing factor"
        //		as a property of the drawing.
        //		Renamed to "smoothing tolerance"
        //		while KaleidoPaint 3.0 was still in beta.
        //
        //	Version 1.9
        //		Version 1.9 adds the "fill color"
        //		as a property of the drawing.
        //
        //	Version 1.10
        //		Version 1.10 adds the "log2 unit cell resolution"
        //		as a property of the drawing.
        //

        //	Version 1.1 -> 1.2
        //
        //	KaleidoPaint's internal code now uses the base+brightness factorization,
        //	so when reading old files we'll need to convert.
        //	Of course once the user edits the drawing and re-saves it,
        //	KaleidoPaint will write the file using the new format.
        //
        val theColorsNeedLightnessToBrightnessConversion =
            (theFileFormatMajorVersionNumber == 1L && theFileFormatMinorVersionNumber <= 1)

        //	Version 1.2 -> 1.3
        //
        val theColorsNeedGammaEncodedToLinearConversion =
            (theFileFormatMajorVersionNumber == 1L && theFileFormatMinorVersionNumber <= 2)

        //	Version 1.3 -> 1.4
        //
        val theColorsNeedSRGBtoP3Conversion =
            (theFileFormatMajorVersionNumber == 1L && theFileFormatMinorVersionNumber <= 3)

        //	Version 1.4 -> 1.5
        //
        val theColorsNeedFactoredToUnfactoredConversion =
            (theFileFormatMajorVersionNumber == 1L && theFileFormatMinorVersionNumber <= 4)

        //	Version 1.5 -> 1.6
        //
        val theWallpaperGroupIsInOldFormat =
            (theFileFormatMajorVersionNumber == 1L && theFileFormatMinorVersionNumber <= 5)

        //	Version 1.6 -> 1.7
        //
        val thePropertiesNeedUpdating =
            (theFileFormatMajorVersionNumber == 1L && theFileFormatMinorVersionNumber <= 6)

        //	In file format version 1.4 and earlier,
        //	the background color and the brush color each required
        //	a token for the divider "|" and a token for the brightness.
        val theMinNumTokens = (if (theColorsNeedFactoredToUnfactoredConversion) 48 else 44)
        if (theNumTokens < theMinNumTokens) {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason =
                    "drawing file is impossibly short - even an empty drawing must contain ${theMinNumTokens} tokens"
            )
        }

        //	Read the global information.

        if (t[4] != "wallpaper" || t[5] != "group") {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "'wallpaper group' not found at expected position"
            )
        }
        val theWallpaperGroupRawValue: String
        if (theWallpaperGroupIsInOldFormat) {

            //	We're reading file format 1.5 or earlier, which
            //	stored the wallpaper group as an integer ∈ {0, … , 16}.
            val theLegacyIndexingScheme =
                listOf(
                    "○",
                    "2222",
                    "333",
                    "442",
                    "632",
                    "*2222",
                    "*333",
                    "*442",
                    "*632",
                    "22*",
                    "2*22",
                    "3*3",
                    "4*2",
                    "**",
                    "22×",
                    "*×",
                    "××",
                )

            val theWallpaperGroupAsInt =
                swiftInt(t[6])
                    ?: throw KaleidoPaintFileEncodingError.fileFormatError(
                        reason = "unparsable legacy wallpaper group number"
                    )
            if (
                theWallpaperGroupAsInt < 0 || theWallpaperGroupAsInt >= theLegacyIndexingScheme.size
            ) {
                throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "invalid legacy wallpaper group number"
                )
            }
            theWallpaperGroupRawValue = theLegacyIndexingScheme[theWallpaperGroupAsInt.toInt()]
        } else {
            //	We're reading file format 1.6 or later, which
            //	stores the wallpaper group as a string
            //	containing the group's name in orbifold notation
            theWallpaperGroupRawValue = t[6]
        }
        val theWallpaperGroup =
            WallpaperGroup.fromRawValue(theWallpaperGroupRawValue)
                ?: throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason =
                        "invalid wallpaper group name (orbifold notation expected, ∈ {'○', '2222', '333', '442', '632', '*2222', '*333', '*442', '*632', '22*', '2*22', '3*3', '4*2', '**', '22×', '*×', '××'})"
                )
        itsWallpaperGroup = theWallpaperGroup

        if (t[7] != "unit" || t[8] != "cell" || t[9] != "placement") {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "'unit cell placement' not found at expected position"
            )
        }
        //	Port note:  Swift's "guard let a = …, let b = … else { throw }"
        //	reads its values one at a time and stops at the first failure.
        //	Here and below, each value carries its own "?: throw" to do the same.
        fun invalidPlacement(): Nothing {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "invalid data for 'unit cell placement'"
            )
        }
        val theCorner0 = swiftDouble(t[10]) ?: invalidPlacement()
        val theCorner1 = swiftDouble(t[11]) ?: invalidPlacement()
        val theTranslations00 = swiftDouble(t[12]) ?: invalidPlacement()
        val theTranslations01 = swiftDouble(t[13]) ?: invalidPlacement()
        val theTranslations10 = swiftDouble(t[14]) ?: invalidPlacement()
        val theTranslations11 = swiftDouble(t[15]) ?: invalidPlacement()
        val placementValues =
            listOf(
                theCorner0,
                theCorner1,
                theTranslations00,
                theTranslations01,
                theTranslations10,
                theTranslations11,
            )
        val placementDeterminant =
            theTranslations00 * theTranslations11 - theTranslations01 * theTranslations10
        if (
            placementValues.any { !it.isFinite() } ||
                !placementDeterminant.isFinite() ||
                placementDeterminant <= 0.0
        )
            invalidPlacement()
        //	Port note:  set as whole values, where the original
        //	assigns the six components one at a time.
        itsUnitCellPlacement.itsCorner = Double2(theCorner0, theCorner1)
        itsUnitCellPlacement.itsTranslations =
            Double2x2(
                Double2(theTranslations00, theTranslations01),
                Double2(theTranslations10, theTranslations11),
            )

        val metric = itsUnitCellPlacement.itsMetricOfDet1
        val inverseCorner =
            itsUnitCellPlacement.itsTranslations.inverse * itsUnitCellPlacement.itsCorner
        if (
            itsUnitCellPlacement.unitCellIsDegenerate() ||
                listOf(
                        metric[0].x,
                        metric[0].y,
                        metric[1].x,
                        metric[1].y,
                        inverseCorner.x,
                        inverseCorner.y,
                    )
                    .any { !it.isFinite() }
        )
            invalidPlacement()

        var theTokenIndex = 16

        //	The current version of KaleidoPaint uses a fixed resolution (11),
        //	but for simplicity the file format still retains a field
        //	for the "log2 unit cell resolution", which we skip over
        //	when reading the file.
        if (
            theFileFormatMajorVersionNumber > 1 ||
                (theFileFormatMajorVersionNumber == 1L && theFileFormatMinorVersionNumber >= 10)
        ) {

            if (
                t[theTokenIndex + 0] != "log2" ||
                    t[theTokenIndex + 1] != "unit" ||
                    t[theTokenIndex + 2] != "cell" ||
                    t[theTokenIndex + 3] != "resolution"
            ) {
                throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "'log2 unit cell resolution' not found at expected position"
                )
            }

            //			guard let theDecodedLog2UnitCellResolution = Int(t[theTokenIndex + 4]) else {
            //				throw KaleidoPaintFileEncodingError.fileFormatError(
            //					reason: "invalid data for 'log2 unit cell resolution'")
            //			}

            theTokenIndex += 5
        } else { //	file format 1.9 or earlier

            //	Those older file formats didn't include
            //	the "log2 unit cell resolution".
        }

        fun readOneLinearDisplayP3Color(): LinearDisplayP3Color {

            fun invalidColor(): Nothing {
                throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "invalid data for color"
                )
            }
            var r = swiftDouble(t[theTokenIndex + 0]) ?: invalidColor()
            var g = swiftDouble(t[theTokenIndex + 1]) ?: invalidColor()
            var b = swiftDouble(t[theTokenIndex + 2]) ?: invalidColor()
            val a = swiftDouble(t[theTokenIndex + 3]) ?: invalidColor() // 	= 1.0
            if (a != 1.0) {
                throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "color opacity must be 1.0"
                )
            }

            if (theColorsNeedFactoredToUnfactoredConversion) { // 	file format 1.4 or earlier

                if (t[theTokenIndex + 4] != "|") {
                    throw KaleidoPaintFileEncodingError.fileFormatError(
                        reason = "color separator bar '|' not found at expected position"
                    )
                }

                var theBrightness =
                    swiftDouble(t[theTokenIndex + 5]) // 	in version 1.1, this is "lightness"
                    ?: throw KaleidoPaintFileEncodingError.fileFormatError(
                            reason = "invalid data for legacy 'background color' brightness"
                        )

                if (theColorsNeedLightnessToBrightnessConversion) {
                    val theConvertedColor = convertColorFromHSLtoHSB(r, g, b, theBrightness)
                    r = theConvertedColor.r
                    g = theConvertedColor.g
                    b = theConvertedColor.b
                    theBrightness = theConvertedColor.brightness
                }
                if (theColorsNeedGammaEncodedToLinearConversion) {
                    val theConvertedColor =
                        convertColorFromGammaEncodedToLinear(r, g, b, theBrightness)
                    r = theConvertedColor.r
                    g = theConvertedColor.g
                    b = theConvertedColor.b
                    theBrightness = theConvertedColor.brightness
                }
                if (theColorsNeedSRGBtoP3Conversion) {
                    val theConvertedColor =
                        convertColorFromSRGBLinearToP3Linear(r, g, b, theBrightness)
                    r = theConvertedColor.r
                    g = theConvertedColor.g
                    b = theConvertedColor.b
                    theBrightness = theConvertedColor.brightness
                }

                r *= theBrightness
                g *= theBrightness
                b *= theBrightness

                theTokenIndex += 6
            } else { //	file format is version 1.5 or later
                theTokenIndex += 4
            }

            val theLinearDisplayP3Color = LinearDisplayP3Color(r = r, g = g, b = b, a = a)

            return theLinearDisplayP3Color
        }

        if (t[theTokenIndex + 0] != "background" || t[theTokenIndex + 1] != "color") {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "'background color' not found at expected position"
            )
        }
        theTokenIndex += 2
        itsBackgroundColor = readOneLinearDisplayP3Color()

        if (t[theTokenIndex] != "brush" || t[theTokenIndex + 1] != "color") {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "'brush color' not found at expected position"
            )
        }
        theTokenIndex += 2
        itsBrushColor = readOneLinearDisplayP3Color()

        if (
            theFileFormatMajorVersionNumber > 1 ||
                (theFileFormatMajorVersionNumber == 1L && theFileFormatMinorVersionNumber >= 9)
        ) {

            if (t[theTokenIndex] != "fill" || t[theTokenIndex + 1] != "color") {
                throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "'fill color' not found at expected position"
                )
            }
            theTokenIndex += 2
            itsFillColor = readOneLinearDisplayP3Color()
        }

        if (t[theTokenIndex] != "brush" || t[theTokenIndex + 1] != "thickness") {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "'brush thickness' not found at expected position"
            )
        }
        val theBrushThickness =
            swiftDouble(t[theTokenIndex + 2])
                ?: throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "invalid data for 'brush thickness'"
                )
        itsBrushThickness =
            (if (thePropertiesNeedUpdating)
                //	Version 1.6 and earlier interpreted "thickness"
                //		as a half-thickness, so double it
                2.0 * theBrushThickness
            else theBrushThickness)
        theTokenIndex += 3

        if (
            theFileFormatMajorVersionNumber > 1 ||
                (theFileFormatMajorVersionNumber == 1L && theFileFormatMinorVersionNumber >= 8)
        ) {

            if (
                t[theTokenIndex] != "smoothing" ||
                    (t[theTokenIndex + 1] != "tolerance"
                    //	The term "smoothing factor" was used briefly
                    //	while KaleidoPaint 3.0 was in beta,
                    //	so it might still be present in some
                    //	of Francine's, Geneviève's and/or my drawings.
                    && t[theTokenIndex + 1] != "factor")
            ) {
                throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "'smoothing tolerance' not found at expected position"
                )
            }
            val theSmoothingTolerance =
                swiftDouble(t[theTokenIndex + 2])
                    ?: throw KaleidoPaintFileEncodingError.fileFormatError(
                        reason = "invalid data for 'smoothing tolerance'"
                    )
            itsSmoothingTolerance = theSmoothingTolerance
            theTokenIndex += 3
        }

        if (t[theTokenIndex] != "show" || t[theTokenIndex + 1] != "singularities") {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "'show singularities' not found at expected position"
            )
        }
        if (t[theTokenIndex + 2] == "false") {
            itsShowSingularitiesFlag = false
        } else if (t[theTokenIndex + 2] == "true") {
            itsShowSingularitiesFlag = true
        } else {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "invalid data for 'show singularities' (must be 'false' or 'true')"
            )
        }
        theTokenIndex += 3

        if (
            t[theTokenIndex] != "color" ||
                t[theTokenIndex + 1] != "by" ||
                t[theTokenIndex + 2] != "symmetry"
        ) {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "'color by symmetry' not found at expected position"
            )
        }
        if (t[theTokenIndex + 3] == "false") {
            itsColorBySymmetryFlag = false
        } else if (t[theTokenIndex + 3] == "true") {
            itsColorBySymmetryFlag = true
        } else {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "invalid data for 'show singularities' (must be 'false' or 'true')"
            )
        }
        theTokenIndex += 4

        if (
            theFileFormatMajorVersionNumber > 1 ||
                (theFileFormatMajorVersionNumber == 1L && theFileFormatMinorVersionNumber >= 1)
        ) {

            if (
                t[theTokenIndex] != "content" ||
                    t[theTokenIndex + 1] != "is" ||
                    t[theTokenIndex + 2] != "locked"
            ) {
                throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "'content is locked' not found at expected position"
                )
            }
            if (t[theTokenIndex + 3] == "false") {
                itsContentIsLocked = false
            } else if (t[theTokenIndex + 3] == "true") {
                itsContentIsLocked = true
            } else {
                throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "invalid data for 'content is locked' (must be 'false' or 'true')"
                )
            }
            theTokenIndex += 4
        } else {
            itsContentIsLocked = false // 	legacy files assumed unlocked
        }

        //	Read the flexible list of drawing elements.

        //	The list must begin with an "elements" label
        //	and end with a "no-more-elements" label.
        if (t[theTokenIndex] != "elements") {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "'elements' not found at expected position"
            )
        }
        theTokenIndex += 1
        if (t[theNumTokens - 1] != "no-more-elements") {
            throw KaleidoPaintFileEncodingError.fileFormatError(
                reason = "'no-more-elements' not found at end of file"
            )
        }

        //	The list may continue with any sequence of dots, curves and fills,
        //	until it finishes with the label "no-more-elements".
        //
        //		Note:  We checked (immediately above) that
        //		a "no-more-elements" label appears at the end of the file.
        //		Its presence ensures that the loops below will never
        //		try to read past the end of the array t[].
        //
        while (theTokenIndex < theNumTokens - 1) { // 	t[theNumTokens - 1] == "no-more-elements"

            val theElementType = t[theTokenIndex]
            theTokenIndex += 1

            if (theElementType == "dot") {

                val theDot = Dot()

                //	Read theDot's properties, which may appear in any order.
                while (true) {

                    val thePropertyType = t[theTokenIndex]
                    theTokenIndex += 1

                    if (thePropertyType == "no-more-properties") {
                        break
                    }

                    when (thePropertyType) {
                        "color" -> theDot.itsColor = readOneLinearDisplayP3Color()

                        "location", //	file format version ≤ 1.6
                        "center" -> { //	file format version ≥ 1.7

                            fun invalidCenter(): Nothing {
                                throw KaleidoPaintFileEncodingError.fileFormatError(
                                    reason = "invalid data for dot center"
                                )
                            }
                            val theDotCenter0 = swiftDouble(t[theTokenIndex + 0]) ?: invalidCenter()
                            val theDotCenter1 = swiftDouble(t[theTokenIndex + 1]) ?: invalidCenter()
                            theTokenIndex += 2
                            theDot.itsCenter =
                                Double2(
                                    theDotCenter0,
                                    theDotCenter1,
                                )
                        }

                        "thickness" -> { //	file format version ≤ 1.6
                            //	  interpreted "thickness" as a radius

                            val theDotRadius =
                                swiftDouble(t[theTokenIndex])
                                    ?: throw KaleidoPaintFileEncodingError.fileFormatError(
                                        reason = "invalid data for dot radius"
                                    )
                            theTokenIndex += 1
                            theDot.itsThickness = 2.0 * theDotRadius
                        }

                        "diameter" -> { //	file format version ≥ 1.7

                            val theDotDiameter =
                                swiftDouble(t[theTokenIndex])
                                    ?: throw KaleidoPaintFileEncodingError.fileFormatError(
                                        reason = "invalid data for dot diameter"
                                    )
                            theTokenIndex += 1
                            theDot.itsThickness = theDotDiameter
                        }

                        else ->
                            throw KaleidoPaintFileEncodingError.fileFormatError(
                                reason =
                                    "invalid property type for dot (must be 'color', 'center' or 'diameter')"
                            )
                    }
                }

                itsElements.add(theDot)
            } else if (theElementType == "curve") {

                val theCurve = Curve()

                //	Read theCurve's properties, which may appear in any order,
                //	except that the file must list the SplineNodes
                //	in the order in which they appear on the curve itself.
                //
                while (true) {

                    val thePropertyType = t[theTokenIndex]
                    theTokenIndex += 1

                    if (thePropertyType == "no-more-properties") {
                        break
                    }

                    when (thePropertyType) {
                        "color" -> theCurve.itsColor = readOneLinearDisplayP3Color()

                        "thickness" -> {

                            val theCurveThickness =
                                swiftDouble(t[theTokenIndex])
                                    ?: throw KaleidoPaintFileEncodingError.fileFormatError(
                                        reason = "invalid data for curve thickness"
                                    )
                            theTokenIndex += 1
                            theCurve.itsThickness =
                                (if (thePropertiesNeedUpdating)

                                    //	Version 1.6 and earlier interpreted
                                    //		"thickness" as a half-thickness,
                                    //		so double it
                                    2.0 * theCurveThickness
                                else theCurveThickness)
                        }

                        "node" -> {

                            fun invalidLocation(): Nothing {
                                throw KaleidoPaintFileEncodingError.fileFormatError(
                                    reason = "invalid data for spline node location"
                                )
                            }
                            val theNodeLocation0 =
                                swiftDouble(t[theTokenIndex + 0]) ?: invalidLocation()
                            val theNodeLocation1 =
                                swiftDouble(t[theTokenIndex + 1]) ?: invalidLocation()
                            val theNodeType =
                                SplineNodeType.fromRawValue(t[theTokenIndex + 2])
                                    ?: throw KaleidoPaintFileEncodingError.fileFormatError(
                                        reason = "invalid data for spline node type"
                                    )
                            theTokenIndex += 3

                            val theNode =
                                SplineNode(
                                    location =
                                        Double2(
                                            theNodeLocation0,
                                            theNodeLocation1,
                                        ),
                                    type = theNodeType,
                                )

                            theCurve.itsSpline.append(theNode)
                        }

                        else ->
                            throw KaleidoPaintFileEncodingError.fileFormatError(
                                reason =
                                    "invalid property type for curve (must be 'color', 'thickness' or 'node')"
                            )
                    }
                }

                //	Make sure the curve is properly centered in the unit cell.
                //	This check is needed only for older drawings
                //	(KaleidoPaint 3.0.2 and earlier).  Newly created
                //	drawings will all keep the curve centered automatically.
                theCurve.itsSpline.keepCenteredInUnitCell()

                //	Compute the spline parameters.
                theCurve.itsSpline.refreshParameterization()

                itsElements.add(theCurve)
            } else if (theElementType == "fill") {

                val theFill = Fill()

                //	Read theFill's properties, which may appear in either order.
                //
                while (true) {

                    val thePropertyType = t[theTokenIndex]
                    theTokenIndex += 1

                    if (thePropertyType == "no-more-properties") {
                        break
                    }

                    when (thePropertyType) {
                        "color" -> theFill.itsColor = readOneLinearDisplayP3Color()

                        "location", //	file format version ≤ 1.6
                        "fillPoint" -> { //	file format version ≥ 1.7

                            fun invalidFillPoint(): Nothing {
                                throw KaleidoPaintFileEncodingError.fileFormatError(
                                    reason = "invalid data for flood fill's fillPoint"
                                )
                            }
                            val theFillPoint0 =
                                swiftDouble(t[theTokenIndex + 0]) ?: invalidFillPoint()
                            val theFillPoint1 =
                                swiftDouble(t[theTokenIndex + 1]) ?: invalidFillPoint()
                            theTokenIndex += 2
                            theFill.itsFillPoint =
                                Double2(
                                    theFillPoint0,
                                    theFillPoint1,
                                )
                        }

                        else ->
                            throw KaleidoPaintFileEncodingError.fileFormatError(
                                reason =
                                    "invalid property type for flood fill (must be 'color' or 'fillPoint')"
                            )
                    }
                }

                itsElements.add(theFill)
            } else {
                throw KaleidoPaintFileEncodingError.fileFormatError(
                    reason = "invalid drawing element type (must be 'dot', 'curve' or 'fill')"
                )
            }
        }
    }

    // MARK: -
    // MARK: Animation

    var changeCount: Long = 0

    fun updateModel(): Long {

        //	KaleidoPaint uses no independent simulations or animations.
        //	All animations are in response to the user direct input.

        return changeCount
    }

    // MARK: -
    // MARK: Undo/Redo operations

    fun changeBackgroundColor(to: LinearDisplayP3Color) {
        val newBackgroundColor = to

        val theOldBackgroundColor = itsBackgroundColor

        val theOperation = { backgroundColor: LinearDisplayP3Color ->
            this.itsBackgroundColor = backgroundColor

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theDoOperation = { theOperation(newBackgroundColor) }
        val theUndoOperation = { theOperation(theOldBackgroundColor) }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun appendDrawingElement(drawingElement: DrawingElement) {
        //	Calling appendDrawingElement() is slightly more efficient
        //	than calling the general-purpose function changeElementArray().

        val theDoOperation = {
            this.itsElements.add(drawingElement)

            this.changeCount += 1
            this.itsBaseDrawingTextureLastElementRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theUndoOperation = {
            this.itsElements.removeAt(this.itsElements.size - 1)

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun moveDot(
        dot: Dot,
        from: Double2,
        to: Double2,
    ) {
        val oldPosition = from
        val newPosition = to

        val theOperation = { position: Double2 ->
            dot.itsCenter = position

            this.clearCachedRLERuns(from = dot)

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theDoOperation = { theOperation(newPosition) }
        val theUndoOperation = { theOperation(oldPosition) }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun moveSplineNode(
        curve: Curve,
        node: SplineNode,
        from: Double2,
        to: Double2,
    ) {
        val oldPosition = from
        val newPosition = to

        //	When we move the node, we might need to shift
        //	the whole spline to keep it centered in the unit cell.
        //	Let's compute that shift now, to be ready.
        //
        //		Note: The node is already at the newPosition,
        //		as a result of the user dragging there.
        //		The purpose of moveSplineNode() is to take
        //		the drag that's already happened and put
        //		its overall effect onto the undo/redo stacks.
        //
        //	In most cases theShift will be zero.
        //
        val theShiftToKeepCentered = curve.itsSpline.computeShiftToKeepCenteredInUnitCell()

        val theDoOperation = {

            //	First set the newPosition...
            node.itsNodeLocation = newPosition

            //	... then shift the whole curve to keep it centered.
            curve.itsSpline.applyShift(theShiftToKeepCentered)

            curve.itsSpline.refreshParameterization()
            this.clearCachedRLERuns(from = curve)

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theUndoOperation = {

            //	First undo the shift...
            curve.itsSpline.applyShift(-theShiftToKeepCentered)

            //	... and then set the oldPosition.
            node.itsNodeLocation = oldPosition

            curve.itsSpline.refreshParameterization()
            this.clearCachedRLERuns(from = curve)

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun moveFill(
        fill: Fill,
        from: Double2,
        to: Double2,
    ) {
        val oldPosition = from
        val newPosition = to

        val theOperation = { position: Double2 ->
            fill.itsFillPoint = position

            this.clearCachedRLERuns(from = fill)

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theDoOperation = { theOperation(newPosition) }
        val theUndoOperation = { theOperation(oldPosition) }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun deleteSplineNode(
        curve: Curve,
        node: SplineNode,
    ) {

        val theSpline = curve.itsSpline

        if (theSpline.itsNodes.size < 3) { // 	must keep ≥ 2 nodes (caller also checks this)
            assertionFailure(
                "Internal error:  deleteSplineNode() received a spline with fewer than 3 nodes"
            )
            return
        }

        val theNodeIndex = theSpline.itsNodes.indexOfFirst({ aNode -> aNode === node })
        if (theNodeIndex < 0) {
            assertionFailure(
                "Internal error:  deleteSplineNode() received a node that's not part of the spline"
            )
            return
        }
        val theDeletedNode = theSpline.itsNodes[theNodeIndex]

        val theDoOperation = {
            theSpline.itsNodes.removeAt(theNodeIndex)
            theSpline.refreshParameterization()
            this.clearCachedRLERuns(from = curve)

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theUndoOperation = {
            theSpline.itsNodes.add(theNodeIndex, theDeletedNode)
            theSpline.refreshParameterization()
            this.clearCachedRLERuns(from = curve)

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun splitSplineNode(
        curve: Curve,
        oldNode: SplineNode,
        newNodeA: SplineNode,
        newNodeB: SplineNode,
    ) {

        val theSpline = curve.itsSpline

        val i = theSpline.itsNodes.indexOfFirst({ node -> node === oldNode })
        if (i < 0) {

            assertionFailure(
                "Internal error:  splitSplineNode received an oldNode that's not part of the curve"
            )

            return
        }

        val theDoOperation = {

            //	replaceSubrange(i ... i, with: [newNodeA, newNodeB])
            curve.itsSpline.itsNodes.removeAt(i)
            curve.itsSpline.itsNodes.addAll(i, listOf(newNodeA, newNodeB))
            theSpline.refreshParameterization()
            this.clearCachedRLERuns(from = curve)

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theUndoOperation = {

            //	replaceSubrange(i ... i+1, with: [oldNode])
            curve.itsSpline.itsNodes.removeAt(i + 1)
            curve.itsSpline.itsNodes.removeAt(i)
            curve.itsSpline.itsNodes.add(i, oldNode)
            theSpline.refreshParameterization()
            this.clearCachedRLERuns(from = curve)

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun changeSplineNodeType(
        curve: Curve,
        node: SplineNode,
        from: SplineNodeType,
        to: SplineNodeType,
    ) {
        val oldType = from
        val newType = to

        val theSpline = curve.itsSpline

        val theOperation = { nodeType: SplineNodeType ->
            node.itsNodeType = nodeType
            theSpline.refreshParameterization()
            this.clearCachedRLERuns(from = curve)

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theDoOperation = { theOperation(newType) }
        val theUndoOperation = { theOperation(oldType) }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun changeUnitCellShape(
        oldShape: UnitCellShape,
        newShape: UnitCellShape,
    ) {

        //	Adjust itsTranslations to realize the newShape,
        //	while leaving the translation, rotation and scale
        //	of the drawing more-or-less untouched, so the user
        //	may reliably translate, rotate and zoom the drawing
        //	independently of any Undo/Redo operations.

        val theOperation = { shape: UnitCellShape ->
            this.setUnitCellShape(shape)

            //	Changing the unit cell shape typically requires Brushstrokes
            //	to be drawn slightly differently in the unit cell texture
            //	(using a different ellipse for the brush), which may
            //	invalidate cached flood fill masks.
            this.clearCachedRLERuns()

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsSingularitiesTextureRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theDoOperation = { theOperation(newShape) }
        val theUndoOperation = { theOperation(oldShape) }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun changeUnitCellPlacement(
        oldPlacement: UnitCellPlacement,
        newPlacement: UnitCellPlacement,
    ) {

        //	Note:  This function gets called only in response
        //	to taps on the Realign button.  By contrast,
        //	when the user uses a 2-finger gesture to translate,
        //	rotate or zoom the drawing, the change gets applied
        //	directly, without putting it onto the Undo stack.

        //	Port note:  A UnitCellPlacement is a value in Swift, so the closure
        //	below holds its own copies and installs a fresh copy each time.
        //	Here that takes explicit copy() calls.
        val theOldPlacementCopy = oldPlacement.copy()
        val theNewPlacementCopy = newPlacement.copy()

        val theOperation = { placement: UnitCellPlacement ->
            this.itsUnitCellPlacement = placement.copy()

            //	Changing the unit cell placement typically requires Brushstrokes
            //	to be drawn slightly differently in the unit cell texture
            //	(using a different ellipse for the brush), which may
            //	invalidate cached flood fill masks.
            this.clearCachedRLERuns()

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsSingularitiesTextureRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theDoOperation = { theOperation(theNewPlacementCopy) }
        val theUndoOperation = { theOperation(theOldPlacementCopy) }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun changeWallpaperGroup(
        to: WallpaperGroup,
        placement: UnitCellPlacement,
    ) {
        val newWallpaperGroup = to
        val newUnitCellPlacement =
            placement.copy() // 	see the port note in changeUnitCellPlacement()

        val theOldWallpaperGroup = itsWallpaperGroup
        val theOldUnitCellPlacement = itsUnitCellPlacement.copy()

        val theOperation = { wallpaperGroup: WallpaperGroup, unitCellPlacement: UnitCellPlacement ->
            this.itsWallpaperGroup = wallpaperGroup
            this.itsUnitCellPlacement = unitCellPlacement.copy()

            //	Changing itsUnitCellPlacement typically requires Brushstrokes
            //	to be drawn slightly differently in the unit cell texture
            //	(using a different ellipse for the brush), which may
            //	invalidate cached flood fill masks.
            this.clearCachedRLERuns()

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsSingularitiesTextureRedrawRequestCount += 1
            this.itsUndoRedoCount += 1

            //	UserDefaults.standard.set(wallpaperGroup.rawValue, forKey: "default symmetry group")
            this.itsDefaultSymmetryGroupObserver?.invoke(wallpaperGroup)
            Unit
        }
        val theDoOperation = { theOperation(newWallpaperGroup, newUnitCellPlacement) }
        val theUndoOperation = { theOperation(theOldWallpaperGroup, theOldUnitCellPlacement) }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun changeColor(
        of: List<DrawingElement>,
        to: LinearDisplayP3Color,
    ) {
        val elements = of.toList() // 	a Swift Array parameter is a copy
        val newColor = to

        val theFirstElement =
            elements.firstOrNull() // 	should never fail
            ?: return
        val theOldColor = theFirstElement.itsColor

        val theOperation = { color: LinearDisplayP3Color ->
            for (theElement in elements) {
                theElement.itsColor = color
            }

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theDoOperation = { theOperation(newColor) }
        val theUndoOperation = { theOperation(theOldColor) }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun changeThickness(
        of: List<Brushstroke>, // 	listed in the same order they get drawn
        from: Double,
        to: Double,
    ) {
        val brushstrokes = of.toList() // 	a Swift Array parameter is a copy
        val oldThickness = from
        val newThickness = to

        val theOperation = { thickness: Double ->
            for (theBrushstroke in brushstrokes) {
                theBrushstroke.itsThickness = thickness
            }

            //	theFirstBrushstroke is not just the first item in the Array,
            //	it's also the first of those brushstrokes to get drawn at render time.
            val theFirstBrushstroke = brushstrokes.firstOrNull()
            if (theFirstBrushstroke != null) { // 	should never fail

                //	The Brushstrokes' thickness might affect the extent
                //	of subsequent flood fills, so when we re-render the scene
                //	we'll need to recompute all fills that come after theFirstBrushstroke.
                this.clearCachedRLERuns(from = theFirstBrushstroke)
            }

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theDoOperation = { theOperation(newThickness) }
        val theUndoOperation = { theOperation(oldThickness) }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun changeElementArray(
        from: List<DrawingElement>,
        to: List<DrawingElement>,
    ) {
        val oldElementArray = from.toList() // 	a Swift Array parameter is a copy
        val newElementArray = to.toList()

        //	While it would be correct to delete all RLE runs
        //	from both the oldElementArray and the newElementArray,
        //	for better performance we may check whether the two Arrays
        //	share a common initial sequence and, if so, avoid needlessly
        //	deleting and recomputing the RLE runs for that initial sequence.

        val theMinNumElements = minOf(oldElementArray.size, newElementArray.size)
        val theFirstDifferenceIndex =
            (0 until theMinNumElements).firstOrNull({ i ->
                oldElementArray[i] !== newElementArray[i]
            }) ?: theMinNumElements

        val theOperation = { oldArray: List<DrawingElement>, newArray: List<DrawingElement> ->
            this.itsElements = newArray.toMutableList()

            //	Clear unneeded RLE runs on the old Array
            //	to reduce memory demands on the Undo stack.
            for (i in theFirstDifferenceIndex until oldArray.size) {
                val theElement = oldArray[i]
                if (theElement is Fill) {
                    theElement.itsCachedRLERunsBuffer = null
                }
            }

            //	Clear unneeded RLE runs on the new Array to let
            //	the Renderer know that it needs to recompute them.
            for (i in theFirstDifferenceIndex until newArray.size) {
                val theElement = newArray[i]
                if (theElement is Fill) {
                    theElement.itsCachedRLERunsBuffer = null
                }
            }

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theDoOperation = { theOperation(oldElementArray, newElementArray) }
        val theUndoOperation = { theOperation(newElementArray, oldElementArray) }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun changeNothing() {

        //	Do nothing.
        //	Please see the call to this function in KaleidoPaintContentView
        //	for an explanation of why this is useful.

        val theNullOperation = {
            this.itsUndoRedoCount += 1
        }

        doSomethingUndoably(
            doOperation = theNullOperation,
            undoOperation = theNullOperation,
        )
    }

    fun changeLegacyDrawingBrushstrokeThicknesses(
        from: List<Double?>,
        to: List<Double?>,
    ) {
        val oldThicknessesArray = from.toList() // 	a Swift Array parameter is a copy
        val newThicknessesArray = to.toList()

        //	I'm not keen on passing data in parallel Arrays,
        //	but I was even less keen on writing the code
        //	needed to make a proper copy of itsDrawingElements,
        //	so here we are.  Let's at least make sure
        //	the oldThicknessesArray and the newThicknessesArray
        //	have the correct length.
        //
        val theElementCount = itsElements.size
        if (
            oldThicknessesArray.size != theElementCount ||
                newThicknessesArray.size != theElementCount
        ) {

            assertionFailure(
                "changeLegacyDrawingBrushstrokeThicknesses() received arrays of incorrect length"
            )
            return
        }

        val theOperation = { thicknessArray: List<Double?> ->

            //	Install the new brushstroke thicknesses
            for (i in 0 until theElementCount) {
                val theElement = this.itsElements[i]
                if (theElement is Brushstroke) {
                    val theNewThickness = thicknessArray[i]
                    if (theNewThickness != null) {
                        theElement.itsThickness = theNewThickness
                    } else {
                        assertionFailure("newThicknessesArray is missing a Brushstroke thickness")
                    }
                }
            }

            this.clearCachedRLERuns()

            this.changeCount += 1
            this.itsBaseDrawingTextureFullRedrawRequestCount += 1
            this.itsUndoRedoCount += 1
        }
        val theDoOperation = { theOperation(newThicknessesArray) }
        val theUndoOperation = { theOperation(oldThicknessesArray) }

        doSomethingUndoably(
            doOperation = theDoOperation,
            undoOperation = theUndoOperation,
        )
    }

    fun doSomethingUndoably(
        doOperation: () -> Unit,
        undoOperation: () -> Unit,
    ) {

        val theUndoManager = itsUndoManager ?: return

        doOperation()

        theUndoManager.registerUndo {

            //	When the user requests an Undo action,
            //	the UndoManager will
            //
            //	1. Swap the undo and redo queues,
            //
            //	2. call this code,
            //
            this.doSomethingUndoably(
                doOperation = undoOperation,
                undoOperation = doOperation,
            )
            //
            //	3. and then swap the undo and redo queues back again.
            //
            //	So this closure must call registerUndo() synchronously,
            //	before the UndoManager swaps the undo and redo queues back.
            //	If we instead called registerUndo() within a Task,
            //	it wouldn't get executed until after the undo and redo queues
            //	had been swapped back.
        }
    }

    fun clearCachedRLERuns(from: DrawingElement? = null) {
        val startingElement = from

        val theFirstElement = itsElements.firstOrNull() ?: return // 	itsElements is empty
        val theStartingElement = startingElement ?: theFirstElement

        val theStartingIndex =
            itsElements.indexOfFirst({ element ->
                element === theStartingElement
            })
        if (theStartingIndex < 0) {
            return //	should never occur
        }

        val theAffectedElements = itsElements.drop(theStartingIndex)

        for (theElement in theAffectedElements) {

            if (theElement is Fill) {

                theElement.itsCachedRLERunsBuffer = null
            }
        }
    }

    // MARK: -
    // MARK: Aspect ratio

    fun getUnitCellShape(): UnitCellShape {

        val theRigidity = itsWallpaperGroup.torusGroup.itsRigidity
        val theTranslations = itsUnitCellPlacement.itsTranslations

        val theAspectRatio: Double
        val theShear: Double
        when (theRigidity) {
            Rigidity.fullyFlexible -> {

                val theComplexRatio =
                    complexQuotient(
                        numerator = theTranslations[1],
                        denominator = theTranslations[0],
                    )

                theAspectRatio = theComplexRatio[1]
                theShear = theComplexRatio[0]
            }

            Rigidity.rectangular -> {

                theAspectRatio = (length(theTranslations[1]) / length(theTranslations[0]))
                theShear = 0.0
            }

            Rigidity.rhombic -> {

                //	The rhombus has a "main diagonal" whose length is

                val theMainDiagonalLength = length(theTranslations[0] + theTranslations[1])

                //	and a "cross diagonal" whose length is

                val theCrossDiagonalLength = length(theTranslations[1] - theTranslations[0])

                //	The aspect ratio is the ratio of those two lengths

                theAspectRatio =
                    (if (theMainDiagonalLength > 0.0) // 	should never fail
                     theCrossDiagonalLength / theMainDiagonalLength
                    else 1.0)
                theShear = 0.0
            }

            Rigidity.rigid -> { // 	should never occur

                theAspectRatio = 1.0
                theShear = 0.0
            }
        }

        return UnitCellShape(
            aspectRatio = theAspectRatio,
            shear = theShear,
        )
    }

    fun setUnitCellShape(unitCellShape: UnitCellShape) {

        val theRigidity = itsWallpaperGroup.torusGroup.itsRigidity
        var theTranslations = itsUnitCellPlacement.itsTranslations

        when (theRigidity) {
            Rigidity.fullyFlexible -> {

                val theComplexRatio =
                    Double2(
                        unitCellShape.shear,
                        unitCellShape.aspectRatio,
                    )

                val theOldArea = theTranslations.determinant

                theTranslations =
                    theTranslations.withColumn(
                        1,
                        complexProduct(
                            z = theTranslations[0],
                            w = theComplexRatio,
                        ),
                    )

                val theNewArea = theTranslations.determinant

                if (theNewArea > 0.0) { // 	should never fail

                    val theFactor = sqrt(theOldArea / theNewArea)

                    theTranslations *= theFactor
                }
            }

            Rigidity.rectangular -> {

                val theOldAspectRatio = (length(theTranslations[1]) / length(theTranslations[0]))

                val theNewAspectRatio = unitCellShape.aspectRatio

                //	In practice this clamping should never be needed,
                //	but let's clamp anyhow just to be safe.
                val theOldClampedAspectRatio = minOf(maxOf(theOldAspectRatio, 0.001), 1000.0)

                val theFactor = sqrt(theNewAspectRatio / theOldClampedAspectRatio)

                theTranslations = theTranslations.withColumn(0, theTranslations[0] / theFactor)
                theTranslations = theTranslations.withColumn(1, theTranslations[1] * theFactor)
            }

            Rigidity.rhombic -> {

                //	See comments for the .rhombic case in getUnitCellShape() above.

                val theMainDiagonal = theTranslations[0] + theTranslations[1]
                val theCrossDiagonal = theTranslations[1] - theTranslations[0]

                val theMainDiagonalLength = length(theMainDiagonal)
                val theCrossDiagonalLength = length(theCrossDiagonal)

                if (theMainDiagonalLength > 0.0 && theCrossDiagonalLength > 0.0) {

                    val theDoubleArea = theMainDiagonalLength * theCrossDiagonalLength

                    val theNewAspectRatio = unitCellShape.aspectRatio

                    val theNewMainDiagonalLength = sqrt(theDoubleArea / theNewAspectRatio)
                    val theNewCrossDiagonalLength = sqrt(theDoubleArea * theNewAspectRatio)

                    val theNewMainDiagonal =
                        (theMainDiagonal * (theNewMainDiagonalLength / theMainDiagonalLength))

                    val theNewCrossDiagonal =
                        (theCrossDiagonal * (theNewCrossDiagonalLength / theCrossDiagonalLength))

                    theTranslations =
                        theTranslations.withColumn(
                            0,
                            0.5 * theNewMainDiagonal - 0.5 * theNewCrossDiagonal,
                        )

                    theTranslations =
                        theTranslations.withColumn(
                            1,
                            0.5 * theNewMainDiagonal + 0.5 * theNewCrossDiagonal,
                        )
                } else { //	should never occur

                    theTranslations = Double2x2.identity
                }
            }

            Rigidity.rigid -> {
                //	should never occur
            }
        }

        itsUnitCellPlacement.itsTranslations = theTranslations
    }

    // MARK: -
    // MARK: Touch handling - tap

    fun singleTapForDrawing(at: DisplayPoint) {
        val tapPoint = at

        //	Ignore single taps while content is locked.
        if (itsContentIsLocked) {
            return
        }

        precondition(
            tapPoint.viewWidth > 0.0 && tapPoint.viewHeight > 0.0,
            "doubleTapForDrawing() received tap in view of zero width or zero height",
        )

        val theSingleTapPointInStrictUnitCellCoordinates =
            convertDisplayCoordinatesToStrictUnitCellCoordinates(
                tapPoint,
                unitCellPlacement = itsUnitCellPlacement,
            )

        val theNewDot =
            Dot(
                color = itsBrushColor,
                center = theSingleTapPointInStrictUnitCellCoordinates,
                thickness = itsBrushThickness,
            )

        appendDrawingElement(theNewDot)
    }

    fun doubleTapForDrawing(at: DisplayPoint) {
        val tapPoint = at

        //	Ignore double taps while content is locked.
        if (itsContentIsLocked) {
            return
        }

        precondition(
            tapPoint.viewWidth > 0.0 && tapPoint.viewHeight > 0.0,
            "doubleTapForDrawing() received tap in view of zero width or zero height",
        )

        val theDoubleTapPointInStrictUnitCellCoordinates =
            convertDisplayCoordinatesToStrictUnitCellCoordinates(
                tapPoint,
                unitCellPlacement = itsUnitCellPlacement,
            )

        val theNewFill =
            Fill(
                color = itsFillColor,
                fillPoint = theDoubleTapPointInStrictUnitCellCoordinates,
            )

        appendDrawingElement(theNewFill)
    }

    //	Port note:  The Swift original reports its result through two SwiftUI
    //	bindings, editorIsShown and editorAnchor.  Here the function returns
    //	where to anchor the Editor, as a point of the view with (0,0)
    //	at the top left and (1,1) at the bottom right, or null
    //	if the tap hit no control handle and the Editor should be hidden.
    fun singleTapForEditing(at: DisplayPoint): Double2? {
        val tapPoint = at

        //	We should never be in Edit mode while the drawing is locked,
        //	but check anyhow, just to be safe.
        if (itsContentIsLocked) {
            return null
        }

        precondition(
            tapPoint.viewWidth > 0.0 && tapPoint.viewHeight > 0.0,
            "singleTapForEditing() received tap in view of zero width or zero height",
        )

        val theTapPointInExtendedUnitCellCoordinates =
            convertDisplayCoordinatesToExtendedUnitCellCoordinates(
                tapPoint,
                unitCellPlacement = itsUnitCellPlacement,
            )

        itsControlHandleHit = possibleControlHandleHit(theTapPointInExtendedUnitCellCoordinates)

        val theEditorAnchor: Double2?

        //	Did the tap hit a control handle?
        val theHitControlHandle = itsControlHandleHit
        if (theHitControlHandle != null) {

            val theHandleCenter =
                convertExtendedUnitCellCoordinatesToDisplayCoordinates(
                    theHitControlHandle.itsHitCenter,
                    unitCellPlacement = itsUnitCellPlacement,
                    viewWidth = tapPoint.viewWidth,
                    viewHeight = tapPoint.viewHeight,
                )

            //	Anchoring the Editor at the control handle's center looks good.
            //	In principle the Editor could instead be anchored to a square
            //	containing the control handle (as in the legacy version of KaleidoPaint)
            //	but doing so would be messy (requiring an Anchor<CGRect>.Source
            //	and GeometryReader, it seems) and there's no obvious advantage.
            //	So let's anchor the popover to the control handle's center
            //	and keep things simple.

            theEditorAnchor =
                Double2(
                    theHandleCenter.x / theHandleCenter.viewWidth,
                    1.0 - (theHandleCenter.y / theHandleCenter.viewHeight),
                )
        } else {

            theEditorAnchor = null
        }

        itsBaseDrawingTextureFullRedrawRequestCount += 1
        changeCount += 1

        return theEditorAnchor
    }

    fun possibleControlHandleHit(
        touchPointInExtendedUnitCellCoordinates: Double2
    ): ControlHandleHit? {

        //	Test each DrawingElement for a control-handle hit.
        //	If several control handles sit close to each other,
        //	select the one closest to the tap point.

        val theFillMarkerRadius = fillMarkerRadius() // 	used only for Fills

        var thePossibleHitControlHandle: ControlHandleHit? = null
        var theTapError = Double.POSITIVE_INFINITY

        for (theElement in itsElements) {

            val theHitControlHandle =
                theElement.hitControlHandle(
                    touchPointInExtendedUnitCellCoordinates =
                        touchPointInExtendedUnitCellCoordinates,
                    wallpaperGroup = itsWallpaperGroup,
                    metricOfDet1 = itsUnitCellPlacement.itsMetricOfDet1,
                    fillMarkerRadius = theFillMarkerRadius,
                )
            if (theHitControlHandle != null) {

                if (theHitControlHandle.itsTapError < theTapError) {

                    thePossibleHitControlHandle = theHitControlHandle
                    theTapError = theHitControlHandle.itsTapError
                }
            }
        }

        return thePossibleHitControlHandle
    }

    // MARK: -
    // MARK: Touch handling - single touch

    fun touchBegan(at: DisplayPoint) {
        val initialTouchPoint = at

        //	Ignore all 1-finger motions while content is locked.
        if (itsContentIsLocked) {
            return
        }

        val theExtendedUnitCellPoint =
            convertDisplayCoordinatesToExtendedUnitCellCoordinates(
                initialTouchPoint,
                unitCellPlacement = itsUnitCellPlacement,
            )

        when (itsTouchMode) {
            TouchMode.draw -> touchBeganForDrawing(at = theExtendedUnitCellPoint)

            TouchMode.edit -> touchBeganForEditing(at = theExtendedUnitCellPoint)
        }
    }

    fun touchMoved(to: DisplayPoint) {
        val touchPoint = to

        //	Note:  Because theDrawingView sets isExclusiveTouch = true,
        //	the user can't possibly lock or unlock the drawing
        //	while a touch is in progress.  The itsContentIsLocked
        //	will be true here iff it was true in touchBegan().
        //
        if (itsContentIsLocked) {
            return
        }

        val theExtendedUnitCellPoint =
            convertDisplayCoordinatesToExtendedUnitCellCoordinates(
                touchPoint,
                unitCellPlacement = itsUnitCellPlacement,
            )

        if (itsCurveInProgress != null) {
            touchMovedForDrawing(at = theExtendedUnitCellPoint)
        } else {
            touchMovedForEditing(at = theExtendedUnitCellPoint)
        }
    }

    fun touchEnded() {

        //	Note:  Because theDrawingView sets isExclusiveTouch = true,
        //	the user can't possibly lock or unlock the drawing
        //	while a touch is in progress.  The itsContentIsLocked
        //	will be true here iff it was true in touchBegan().
        //
        if (itsContentIsLocked) {
            return
        }

        if (itsCurveInProgress != null) {
            touchEndedForDrawing()
        } else {
            touchEndedForEditing()
        }
    }

    fun touchCancelled() {

        //	Note:  Because theDrawingView sets isExclusiveTouch = true,
        //	the user can't possibly lock or unlock the drawing
        //	while a touch is in progress.  The itsContentIsLocked
        //	will be true here iff it was true in touchBegan().
        //
        if (itsContentIsLocked) {
            return
        }

        if (itsCurveInProgress != null) {
            touchCancelledForDrawing()
        } else {
            touchCancelledForEditing()
        }
    }

    // MARK: -
    // MARK: Touch handling - single touch - drawing

    private fun touchBeganForDrawing(at: Double2) {
        val extendedUnitCellPoint = at

        assert(itsCurveInProgress == null) { "unexpected curve-in-progress" }

        //	Choose itsCurveInProgressTouchOffset so that
        //	theOffsetPoint will sit in the unit cell [0,1]×[0,1].

        val theStrictUnitCellPoint =
            convertExtendedUnitCellCoordinatesToStrictUnitCellCoordinates(extendedUnitCellPoint)

        //	In principle theCurveInProgressTouchOffset is an integer,
        //	but of course in practice it might come out as, say,
        //	17.9999999 or 18.0000001.
        val theCurveInProgressTouchOffset = theStrictUnitCellPoint - extendedUnitCellPoint

        itsCurveInProgressTouchOffset =
            Int2(
                round(theCurveInProgressTouchOffset[0]).toInt(),
                round(theCurveInProgressTouchOffset[1]).toInt(),
            )

        //	Initialize the potential basepoints (x,y) with x ∈ {-1,0,+1} and y ∈ {-1,0,+1}.
        initializePotentialBasepoints(
            curveStartInStrictUnitCellCoordinates = theStrictUnitCellPoint
        )

        //	Create an empty curve...
        val theCurveInProgress =
            Curve(
                color = itsBrushColor,
                thickness = itsBrushThickness,
            )

        //	... and then add the starting node.
        val theStartingNode =
            SplineNode(location = theStrictUnitCellPoint, type = SplineNodeType.corner)
        theCurveInProgress.itsSpline.append(theStartingNode)
        theCurveInProgress.itsSpline.refreshParameterization()

        itsCurveInProgress = theCurveInProgress
        itsCurveInProgressTextureRedrawRequestCount += 1
        changeCount += 1
    }

    private fun touchMovedForDrawing(at: Double2) {
        val extendedUnitCellPoint = at

        val theCurveInProgress = itsCurveInProgress ?: return

        val theOffsetPoint = extendedUnitCellPoint + Double2(itsCurveInProgressTouchOffset)

        //	Adaptation for iPencil on iOS
        //
        //	I've never used an iPencil myself, but based
        //	on the test files that Francine Champagne sent me,
        //	it seems that the legacy KaleidoPaint was receiving
        //	a stream of touchesMoved() messages even when
        //	locationInView hadn't changed.  Maybe iPencil
        //	generates touchesMoved() messages continuously,
        //	even when it's not moving???  At the very least,
        //	it offers higher precision ( preciseLocationInView )
        //	and a higher sampling rate ( see coalescedTouchesForTouch ).
        //	I have no immediate plans to revise KaleidoPaint to use
        //	preciseLocationInView and coalescedTouchesForTouch,
        //	but just to be safe let's check whether this new point
        //	is the same as the previous point and if it is, let's ignore it.
        val thePreviousNode = theCurveInProgress.itsSpline.itsNodes.lastOrNull()
        if (thePreviousNode == null) {
            assertionFailure("touchMovedForDrawing() called with empty curve-in-progress")
            return
        }
        if (theOffsetPoint == thePreviousNode.itsNodeLocation) { // 	check for exact equality
            return
        }

        if (updatePotentialBasepoints(newPoint = theOffsetPoint)) {

            //	Note on curve-in-progress
            //
            //	As the user moves his/her finger, we keep adding SplineNodes
            //	with a minimum of processing.  Each new SplineNode is temporarily
            //	marked as a .corner,  so that the curve-in-progress may be drawn
            //	as a series of dots connected by (very short!) straight lines.
            //
            //	Only after the user lifts his/her finger will the curve-in-progress be complete,
            //	at which time touchEndedForDrawing() will decide on the actual corner nodes
            //	(currently it sets no internal corner nodes), and then, along the interior
            //	of each corner-node-to-corner-node arc, it will call ramerDouglasPeucker()
            //	to eliminate the many superfluous interior nodes, and finally
            //	call refreshParameterization() again to recompute the ξ parameters.

            val theNewNode = SplineNode(location = theOffsetPoint, type = SplineNodeType.corner)
            theCurveInProgress.itsSpline.append(theNewNode)
            theCurveInProgress.itsSpline.refreshParameterization()

            itsCurveInProgressTextureRedrawRequestCount += 1
            changeCount += 1
        }
    }

    private fun touchEndedForDrawing() {

        val theCurveInProgress = itsCurveInProgress ?: return

        //	Select one of the valid basepoints.
        //
        //	Port note:  In Swift this is whichever element the Set happens
        //	to list first, which differs from one launch of the app to the next.
        //	Here the set keeps its elements in the order they were added,
        //	so it's the first one tried that is still valid.  Every valid
        //	basepoint gives the same drawing;  they differ only in which copy
        //	of the unit cell the curve's coordinates are stored relative to.
        val theBasepoint =
            itsCurveInProgressValidBasepoints.firstOrNull() // 	should never occur
            ?: return

        //	We want to clear the curve-in-progress
        //	whether or not we encounter an error.
        itsCurveInProgress = null
        itsCurveInProgressValidBasepoints = mutableSetOf()
        itsCurveInProgressAcceptsNewPoints = false
        itsCurveInProgressTextureRedrawRequestCount += 1 // 	to clear the texture
        changeCount += 1

        //	Renormalize itsCurveInProgress relative to theBasepoint,
        //	so that the whole curve stays within the padded safe region.
        for (theNode in theCurveInProgress.itsSpline.itsNodes) {

            theNode.itsNodeLocation -= Double2(theBasepoint)
        }

        val theNumNodes = theCurveInProgress.itsSpline.itsNodes.size

        //	The user interface should never call touchBegan()
        //	without also calling touchMoved(), so a curve should
        //	always have at least two nodes.
        if (theNumNodes < 2) {
            return
        }

        //	The first and last nodes count as special cases of corners,
        //	and get treated the same way (the spline's second derivatives get
        //	set to zero at all corners, including first and last nodes).
        theCurveInProgress.itsSpline.itsNodes[0].itsNodeType = SplineNodeType.corner
        theCurveInProgress.itsSpline.itsNodes[theNumNodes - 1].itsNodeType = SplineNodeType.corner

        //	An earlier version of KaleidoPaint tried to guess
        //	where the user intended the corners to be, but
        //	it missed about half the time.  So let's just make
        //	all interior nodes be smooth nodes, with the expectation
        //	that the user will then manually change smooth nodes
        //	to corner nodes where desired (using Edit mode).
        //
        //		Note:  If I ever revert to having KaleidoPaint
        //		try to guess where to put the corners, then
        //		the code below will need to call ramerDouglasPeucker()
        //		once for each corner-to-corner arc.
        //
        for (i in 1 until (theNumNodes - 1)) {
            theCurveInProgress.itsSpline.itsNodes[i].itsNodeType = SplineNodeType.smooth
        }

        //	Smooth the arc in two phases:

        //	First take the raw points generated by the user's
        //	(possibly shaky!) finger and remove most of them,
        //	with the goal of eliminating random wobbliness
        //	while retaining the overall shape of the curve.
        //	The Ramer-Douglas-Peucker algorithm works well for this task.
        //	It never removes the first or last nodes.
        //
        //		Note:  This step will never need to be repeated,
        //		even if the user edits the curve.
        //
        ramerDouglasPeucker(theCurveInProgress)

        //	Second, construct a cubic spline connecting the points
        //	that survived the Ramer-Douglas-Peucker algorithm.
        //
        //		Note:  This step will need to be repeated,
        //		each time the user edits the curve.
        //
        theCurveInProgress.itsSpline.refreshParameterization()

        //	Pass theCurveInProgress to the undo/redo mechanism
        //	for installation into the drawing.
        appendDrawingElement(theCurveInProgress)

        //	The code above has already cleared itsCurveInProgress etc.
    }

    private fun ramerDouglasPeucker(curve: Curve) {

        //	The Ramer-Douglas-Peucker algorithm
        //
        //		https://en.wikipedia.org/wiki/Ramer–Douglas–Peucker_algorithm
        //
        //	takes the raw points generated by the user's
        //	(possibly shaky!) finger and removes most of them,
        //	with the goal of eliminating random wobbliness
        //	while retaining the overall shape of the curve.

        //	CubicSpline is a class, so theSpline and curve.itsSpline
        //	refer to the same object.  But itsNodes is an Array,
        //	which is struct (not a class), so if we tried to write
        //		let theNodes = curve.itsSpline.itsNodes
        //	we'd get a copy of the Array, and any changes we made
        //	would have no effect on the original.
        //
        val theSpline = curve.itsSpline

        if (theSpline.itsNodes.size < 3) {
            return
        }

        //	The Ramer-Douglas-Peucker algorithm operates recursively.
        //	Given a series of points, it always returns the first and last nodes,
        //	along with any interior nodes that it wants to preserve.
        //
        val theRamerDouglasPeuckerOutput: List<SplineNode> =
            (listOf(theSpline.itsNodes[0]) // 	first node
            +
                ramerDouglasPeuckerInteriorNodes( //	interior nodes (if any)
                    between = 0,
                    and = theSpline.itsNodes.size - 1,
                    inSpline = theSpline,
                    tolerance = itsSmoothingTolerance,
                ) +
                listOf(theSpline.itsNodes[theSpline.itsNodes.size - 1]) // 	last node
            )

        theSpline.itsNodes = theRamerDouglasPeuckerOutput.toMutableList()
    }

    private fun ramerDouglasPeuckerInteriorNodes(
        between: Int,
        and: Int,
        inSpline: CubicSpline, // 	CubicSpline is a class, so passed by reference
        tolerance: Double,
    ): List<SplineNode> {
        val startIndex = between
        val endIndex = and
        val spline = inSpline

        //	Handle the trivial case that the curve
        //	has no interior nodes at all, to keep
        //	the rest of the code simple.
        if (endIndex - startIndex < 2) {
            return listOf()
        }

        //	We cull points based on the UnitCellPlacement
        //	at the moment the user draws the curve.
        //	Different metrics might give slightly different results.
        //
        //	We can to judge distances based not on the metric
        //	of determinant 1, but rather in proportion
        //	to roughly the linear size of the unit cell
        //	in drawing coordinates.
        //
        //		Note: The check for UnitCellIsNondegenerate()
        //		should ensure that the determinant is never
        //		too close to zero.
        //
        val theUnitCellSize = sqrt(fabs(itsUnitCellPlacement.itsTranslations.determinant))
        val theMetric = theUnitCellSize * itsUnitCellPlacement.itsMetricOfDet1

        val p0 = spline.itsNodes[startIndex].itsNodeLocation
        val p1 = spline.itsNodes[endIndex].itsNodeLocation

        //	Compute the vector connecting the first point to the last point.
        val theParallelVector = p1 - p0
        val theTotalLength =
            sqrt(
                theParallelVector[0] * theMetric[0][0] * theParallelVector[0] +
                    theParallelVector[0] * theMetric[0][1] * theParallelVector[1] +
                    theParallelVector[1] * theMetric[1][0] * theParallelVector[0] +
                    theParallelVector[1] * theMetric[1][1] * theParallelVector[1]
            )

        //	We want to find the interior point furthest
        //	from the line through the endpoints.
        var theFurthestNodeIndex = 0 // 	to get overwritten in code below
        var theFurthestDistance = -1.0 // 	to get overwritten in code below

        //	If the curve is a closed loop, then there is no
        //	"approximating line segment" and the standard
        //	Ramer-Douglas-Peucker algorithm requires an easy modification.
        //	Even if the curve if only approximately a closed loop,
        //	it seems more effective to treat it as one.
        //
        if (theTotalLength < tolerance) { // 	endpoints are closer than the tolerance

            //	Find the node that's furthest from the midpoint
            //	of the two nearly-coincident end nodes.

            val theLoopBasepoint = 0.5 * (p0 + p1)

            for (i in (startIndex + 1)..(endIndex - 1)) {

                val p = spline.itsNodes[i].itsNodeLocation

                val v = p - theLoopBasepoint

                val theDistance =
                    sqrt(
                        v[0] * theMetric[0][0] * v[0] +
                            v[0] * theMetric[0][1] * v[1] +
                            v[1] * theMetric[1][0] * v[0] +
                            v[1] * theMetric[1][1] * v[1]
                    )

                if (theDistance > theFurthestDistance) {

                    theFurthestNodeIndex = i
                    theFurthestDistance = theDistance
                }
            }
        } else { //	endpoints are sufficiently distant (typical case)

            //	Find the node that's furthest from the line
            //	that connects aFirstNode to aLastNode.

            //	Compute a unit-length normal vector perpendicular to theParallelVector.

            //	The normal vector n should be orthogonal
            //	to the parallel vector v relative to the metric M,
            //
            //		( n₀ n₁ )( M₀₀ M₀₁ )( v₀ ) = 0
            //		         ( M₁₀ M₁₁ )( v₁ )
            //
            //	If we compute the partial product
            //
            //		( v₀' ) = ( M₀₀ M₀₁ )( v₀ )
            //		( v₁' )   ( M₁₀ M₁₁ )( v₁ )
            //
            //	then we may set
            //
            //		( n₀ n₁ ) = ( -v₁', v₀' ).
            //
            //	Technical note:  It seems likely that n will always
            //	be a 90° counterclockwise (never clockwise) rotation of T,
            //	but I haven't proved this and we don't rely on it.
            var thePerpendicularVector =
                Double2(
                    -(theMetric[1][0] * theParallelVector[0] +
                        theMetric[1][1] * theParallelVector[1]),
                    theMetric[0][0] * theParallelVector[0] + theMetric[0][1] * theParallelVector[1],
                )

            //	The normal vector is already "normal" in the sense
            //	of being orthogonal to the curve, but we want it
            //	to also be "normal" in the sense of having unit length
            //	relative to the metric,
            //
            //		( n₀ n₁ )( M₀₀ M₀₁ )( n₀ ) = 1
            //		         ( M₁₀ M₁₁ )( n₁ )
            //
            val theLength =
                sqrt(
                    thePerpendicularVector[0] * theMetric[0][0] * thePerpendicularVector[0] +
                        thePerpendicularVector[0] * theMetric[0][1] * thePerpendicularVector[1] +
                        thePerpendicularVector[1] * theMetric[1][0] * thePerpendicularVector[0] +
                        thePerpendicularVector[1] * theMetric[1][1] * thePerpendicularVector[1]
                )
            //	It's easy to prove that theLength > 0, but check anyhow before dividing by it.
            precondition(
                theLength > 0.0,
                "thePerpendicularVector has zero length",
            )
            thePerpendicularVector /= theLength

            //	Create a one-form u that evaluates the inner product
            //	of the normal vector n with any vector w
            //
            //		( u₀ u₁ )( w₀ )
            //		         ( w₁ )
            //	=
            //		( n₀ n₁ )( M₀₀ M₀₁ )( w₀ )
            //		         ( M₁₀ M₁₁ )( w₁ )
            //
            val theDistanceEvaluator =
                Double2(
                    thePerpendicularVector[0] * theMetric[0][0] +
                        thePerpendicularVector[1] * theMetric[1][0],
                    thePerpendicularVector[0] * theMetric[0][1] +
                        thePerpendicularVector[1] * theMetric[1][1],
                )

            //	Apply theDistanceEvaluator to either one of the curve's endpoints.
            val theBaseValue = (theDistanceEvaluator[0] * p0[0] + theDistanceEvaluator[1] * p0[1])

            //	Find the intermediate point that's furthest from
            //	the line that passes through the curve's endpoints.
            for (i in (startIndex + 1)..(endIndex - 1)) {

                val p = spline.itsNodes[i].itsNodeLocation

                //	Apply theDistanceEvaluator to theNode.
                val theValue = (theDistanceEvaluator[0] * p[0] + theDistanceEvaluator[1] * p[1])

                //	The distance from the line to theNode
                //	is the difference of the two inner products.
                val theDistance = fabs(theValue - theBaseValue)

                //	Is this the further point we've found so far?
                if (theDistance > theFurthestDistance) {

                    theFurthestNodeIndex = i
                    theFurthestDistance = theDistance
                }
            }
        }

        val theInteriorNodes: List<SplineNode>
        val theAdHocLengthFactor = 64.0
        if (
            //	Do all points lie within aTolerance of the line
            //	through the endpoints (or the basepoint of the loop) ?
            //	Or is some point further away than that?
            //	This is the standard Ramer-Douglas-Peucker criterion.
            theFurthestDistance > tolerance

            //	The standard algorithm yields poor results
            //	for a curve that contains a long straight section
            //	with tightly curved sections on either end.
            //	In such cases the Ramer-Douglas-Peucker algorithm
            //	eliminates all nodes from the straight section,
            //	and then the cubic spline tends to "overshoot" widely
            //	near the straight segment's ends.
            //	To avoid this phenomen, let's try an ad hoc rule
            //	that a long section must include at least one internal node,
            //	whenever one is available.
            || theTotalLength > theAdHocLengthFactor * tolerance
        ) {
            //	Split the curve at the furthest point and
            //	call ramerDouglasPeuckerInteriorNodes() on the two pieces.

            theInteriorNodes =
                (ramerDouglasPeuckerInteriorNodes( //	interior nodes in first half (if any)
                    between = startIndex,
                    and = theFurthestNodeIndex,
                    inSpline = spline,
                    tolerance = tolerance,
                ) +
                    listOf(spline.itsNodes[theFurthestNodeIndex]) // 	furthest node
                    +
                    ramerDouglasPeuckerInteriorNodes( //	interior nodes in second half (if any)
                        between = theFurthestNodeIndex,
                        and = endIndex,
                        inSpline = spline,
                        tolerance = tolerance,
                    ))
        } else { //	theFurthestDistance ≤ aTolerance

            //	All interior points lie within aTolerance
            //	of the segment connecting the curve's endpoints,
            //	so we may ignore them.

            theInteriorNodes = listOf()
        }

        return theInteriorNodes
    }

    private fun touchCancelledForDrawing() {

        itsCurveInProgress = null
        itsCurveInProgressValidBasepoints = mutableSetOf()
        itsCurveInProgressAcceptsNewPoints = false
        itsCurveInProgressTextureRedrawRequestCount += 1 // 	to clear the texture
        changeCount += 1
    }

    // MARK: -
    // MARK: Touch handling - single touch - editing

    private fun touchBeganForEditing(at: Double2) {
        val touchPointInExtendedUnitCellCoordinates = at

        itsCurveInProgress = null // 	unnecessary but safe, and makes our intentions clear

        //	If the touchPointInExtendedUnitCellCoordinates hits a control point
        //	(within some tolerance) remember it.
        //
        itsControlHandleHit = possibleControlHandleHit(touchPointInExtendedUnitCellCoordinates)
    }

    private fun touchMovedForEditing(at: Double2) {
        val extendedUnitCellPoint = at

        //	For now just move the selected point directly.
        //	We'll put the change onto the Undo stack later,
        //	in response to touchEndedForEditing().

        val theControlHandleHit = itsControlHandleHit
        if (theControlHandleHit != null) {

            val theTransformedPoint3 =
                (theControlHandleHit.itsSymmetry *
                    Double3(extendedUnitCellPoint, 1.0) // 	right-to-left matrix action
                )
            val theTransformedPoint =
                Double2(
                    theTransformedPoint3[0],
                    theTransformedPoint3[1],
                )

            //	For Dots and Fills we'll want to normalize theTransformedPoint
            //	to strict unit cell coordinates, so that the user may drag
            //	theDot or theFill as far as desired on the display
            //	without it leaving the area that gets mapped onto the unit cell.
            //
            val theNormalizedPoint = theTransformedPoint - floor(theTransformedPoint)

            val theElement = theControlHandleHit.itsElement

            if (theElement is Dot) {

                theElement.itsCenter = theNormalizedPoint
            }

            if (theElement is Curve) {

                val theNode = theControlHandleHit.itsNode
                if (theNode != null) {

                    //	Use theTransformedPoint (not theNormalizedPoint)
                    //	to maintain continuity with the other nodes in the spline.
                    //
                    theNode.itsNodeLocation = theTransformedPoint

                    theElement.itsSpline.refreshParameterization()
                }
            }

            if (theElement is Fill) {

                theElement.itsFillPoint = theNormalizedPoint
            }

            itsBaseDrawingTextureFullRedrawRequestCount += 1
            changeCount += 1
        }
    }

    private fun touchEndedForEditing() {

        val theControlHandleHit = itsControlHandleHit
        if (theControlHandleHit != null) {

            val theElement = theControlHandleHit.itsElement

            if (theElement is Dot) {

                moveDot(
                    theElement,
                    from = theControlHandleHit.itsHomeCenter,
                    to = theElement.itsCenter,
                )
            }

            if (theElement is Curve) {

                val theNode = theControlHandleHit.itsNode
                if (theNode != null) {

                    moveSplineNode(
                        curve = theElement,
                        node = theNode,
                        from = theControlHandleHit.itsHomeCenter,
                        to = theNode.itsNodeLocation,
                    )
                }
            }

            if (theElement is Fill) {

                moveFill(
                    theElement,
                    from = theControlHandleHit.itsHomeCenter,
                    to = theElement.itsFillPoint,
                )
            }

            itsControlHandleHit = null
        }
    }

    private fun touchCancelledForEditing() {

        //	Move the control point back to where it was when the touch began.

        val theControlHandleHit = itsControlHandleHit
        if (theControlHandleHit != null) {

            val theElement = theControlHandleHit.itsElement

            if (theElement is Dot) {

                theElement.itsCenter = theControlHandleHit.itsHomeCenter
            }

            if (theElement is Curve) {

                val theNode = theControlHandleHit.itsNode
                if (theNode != null) {

                    theNode.itsNodeLocation = theControlHandleHit.itsHomeCenter

                    theElement.itsSpline.refreshParameterization()
                }
            }

            if (theElement is Fill) {

                theElement.itsFillPoint = theControlHandleHit.itsHomeCenter
            }

            itsBaseDrawingTextureFullRedrawRequestCount += 1
            changeCount += 1

            itsControlHandleHit = null
        }
    }

    // MARK: -
    // MARK: Touch handling - single touch basepoints

    private fun initializePotentialBasepoints(curveStartInStrictUnitCellCoordinates: Double2) {

        itsCurveInProgressValidBasepoints = mutableSetOf()

        //	Which choices of basepoint (x,y) with x ∈ {-1,0,+1} and y ∈ {-1,0,+1}
        //	would keep anOffsetPoint in the padded safe region
        //	(see explanation in KaleidoPaintWallpaperGroup.swift) ?
        for (x in -1..+1) {
            for (y in -1..+1) {

                val thePotentialBasepoint = Int2(x, y)

                if (
                    pointSitsInPaddedSafeRegion(
                        extendedUnitCellPoint = curveStartInStrictUnitCellCoordinates,
                        potentialBasepoint = thePotentialBasepoint,
                    )
                ) {

                    itsCurveInProgressValidBasepoints.add(thePotentialBasepoint)
                }
            }
        }

        //	The default basepoint is guaranteed to be valid,
        //	so accept new points.
        itsCurveInProgressAcceptsNewPoints = true
    }

    private fun updatePotentialBasepoints(newPoint: Double2): Boolean {

        //	If some previous point got rejected, then
        //	reject all remaining points in the same curve.
        if (!itsCurveInProgressAcceptsNewPoints) {
            return false
        }

        //	Which nearby choices of basepoint would keep anOffsetPoint
        //	in the padded safe region (see explanation
        //	in KaleidoPaintWallpaperGroup.swift) ?
        val theStillValidBasepoints =
            itsCurveInProgressValidBasepoints.filterTo(
                mutableSetOf(),
                { potentialBasepoint ->
                    pointSitsInPaddedSafeRegion(
                        extendedUnitCellPoint = newPoint,
                        potentialBasepoint = potentialBasepoint,
                    )
                },
            )

        //	Do any valid basepoints remain?
        if (!theStillValidBasepoints.isEmpty()) {

            //	At least one valid basepoint remains, so we may
            //		accept the newPoint,
            //		replace the old set of basepoints
            //			with the new -- possibly smaller -- subset, and
            //		keep accepting new points on the curve.

            itsCurveInProgressValidBasepoints = theStillValidBasepoints
            itsCurveInProgressAcceptsNewPoints = true

            return true //	accept the newPoint
        } else {

            //	No valid basepoints remain, so we must
            //		reject the newPoint,
            //		keep the old set of basepoints, and
            //		stop accepting new points on the curve.

            itsCurveInProgressAcceptsNewPoints = false

            return false //	reject the newPoint
        }
    }

    private fun pointSitsInPaddedSafeRegion(
        extendedUnitCellPoint: Double2,
        potentialBasepoint: Int2,
    ): Boolean {

        //	Does anExtendedUnitCellPoint sit in the "padded safe region"
        //	(as defined in KaleidoPaintWallpaperGroup.swift) relative
        //	to the given choice of basepoint?

        val x = extendedUnitCellPoint[0] - potentialBasepoint[0].toDouble()
        val y = extendedUnitCellPoint[1] - potentialBasepoint[1].toDouble()

        //	Left boundary of padded safe region
        if (x < -1.0 + gSafeRegionInset) {
            return false
        }

        //	Right boundary of padded safe region
        if (x > 2.0 - gSafeRegionInset) {
            return false
        }

        //	Bottom boundary of padded safe region
        if (y < -1.0 + gSafeRegionInset) {
            return false
        }

        //	Top boundary of padded safe region
        if (y > 2.0 - gSafeRegionInset) {
            return false
        }

        //	Bottom-left boundary of padded safe region
        if (x + y < -1.0 + gSafeRegionInset) {
            return false
        }

        //	Top-right boundary of padded safe region
        if (x + y > 3.0 - gSafeRegionInset) {
            return false
        }

        //	(x,y) sits within the padded safe region.
        return true
    }

    // MARK: -
    // MARK: Complex arithmetic

    //	typealias ComplexNumber = SIMD2<Double>
    //	(a Double2 here, with the real part first)

    fun complexProduct(
        z: Double2,
        w: Double2,
    ): Double2 {

        //	(a + bi)(c + di) = (ac - bd) + (ad + bc)i

        val a = z[0]
        val b = z[1]
        val c = w[0]
        val d = w[1]

        val theProduct = Double2(a * c - b * d, a * d + b * c)

        return theProduct
    }

    fun complexQuotient(
        numerator: Double2,
        denominator: Double2,
    ): Double2 {

        //	a + bi   (a + bi)(c - di)   (ac + bd) + (bc - ad)i
        //	------ = ---------------- = ----------------------
        //	c + di   (c + di)(c - di)          c² + d²

        val a = numerator[0]
        val b = numerator[1]
        val c = denominator[0]
        val d = denominator[1]

        val theSquaredMagnitude = c * c + d * d

        val theQuotient: Double2
        if (theSquaredMagnitude > 0.0) {

            theQuotient = (Double2(a * c + b * d, b * c - a * d) / theSquaredMagnitude)
        } else { //	theSquaredMagnitude == 0.0

            assertionFailure("complex division by zero")
            theQuotient = Double2(0.0, 1.0)
        }

        return theQuotient
    }

    // MARK: -
    // MARK: Dynamically sized fill marker

    fun fillMarkerRadius(): Double { // 	mean radius in unit cell coordinates

        //	When the user enlarges a drawing to examine a small part
        //	in fine detail, we want the flood fill markers' size
        //	to remain constant relative the display, not relative
        //	to the unit cell.  So, for example, if the user doubles
        //	the size of the unit cell (in drawing coordinates),
        //	we should halve the size of the flood fill markers
        //	(in unit cell coordinates).
        //
        //		Trivial design note:  I decided not to make this
        //		a computed property, because I didn't want to encourage
        //		my future self or anybody else to call it over and over,
        //		once for every Fill in the list.  It's not a difficult
        //		computation, but even still, as a matter of principle,
        //		better to compute the fill-marker radius
        //		once per texture refresh rather than once per Fill.
        //

        val theNominalMarkerRadius = 0.0078125 // 	mean radius in unit cell coordinates
        val theUnitCellArea = itsUnitCellPlacement.itsTranslations.determinant
        val theScaledMarkerRadius =
            (if (theUnitCellArea > 0.0) // 	should never fail
             theNominalMarkerRadius / sqrt(theUnitCellArea)
            else theNominalMarkerRadius)
        val theCappedMarkerRadius = minOf(0.0078125, theScaledMarkerRadius)

        return theCappedMarkerRadius //	mean radius in unit cell coordinates
    }
}

//	Port note:  The three conversions below return four numbers,
//	which the Swift original returns as a tuple.
class FactoredColor(
    val r: Double, // 	the base color
    val g: Double,
    val b: Double,
    val brightness: Double,
)

//	For use when converting from KaleidoPaint File Format 1.1 to 1.2.
fun convertColorFromHSLtoHSB(
    oldBaseR: Double, // 	the old "base color"
    oldBaseG: Double,
    oldBaseB: Double,
    //	assume a == 1  (that is, opacity α == 1)
    lightness: Double,
): FactoredColor { //	(newBaseR, newBaseG, newBaseB, brightness)

    //	The first time the current version of KaleidoPaint reads
    //	a drawing file in the legacy version 1.1 of the file format,
    //	it will need to convert the legacy "base color + lightness"
    //	to the slightly newer "base color + brightness".
    //	(The base color also changes, of course.)

    var theNewBaseR: Double
    var theNewBaseG: Double
    var theNewBaseB: Double
    val theNewBrightness: Double

    if (lightness <= 0.5) {

        //	The old base color (at lightness = 1/2) and
        //	the new base color (at brightness 1) lie on the same ray
        //	from the origin, so computing the latter from the former is easy.
        var theMaxComponentValue = maxOf(oldBaseR, oldBaseG, oldBaseB)

        //	If numerical errors left us with, say, 0.9999999 instead of 1.0000000,
        //	snap to 1.0 exactly.
        if (theMaxComponentValue > 0.99999) {
            theMaxComponentValue = 1.0
        }

        //	The old base color has lightness 1/2, meaning
        //
        //		(max(R,G,B) + min(R,G,B))/2 = 1/2
        //
        //	so the theMaxComponentValue will always be at least 1/2,
        //	except for the special case of medium grey (R,G,B) = (1/2, 1/2, 1/2)
        //	for which theMaxComponentValue will be exactly 1/2.
        //	Thus, for valid data, it's always safe to divide by theMaxComponentValue.
        //	To guard against invalid data, clamp to 1/2.  (This might also have
        //	the harmless side-effect of rounding 0.4999999 up to 0.5000000.)
        if (theMaxComponentValue < 0.5) {
            theMaxComponentValue = 0.5
        }

        //	Rescale the base color to have maximum component value 1.0.
        val theFactor = 1.0 / theMaxComponentValue
        theNewBaseR = oldBaseR * theFactor
        theNewBaseG = oldBaseG * theFactor
        theNewBaseB = oldBaseB * theFactor

        //	The old lightness determines the new brightness.
        theNewBrightness = 2.0 * lightness * theMaxComponentValue
    } else {
        //	The old base color (at lightness = 1/2) and
        //	the new base color (at brightness 1) lie on different rays
        //	from the origin, so to compute the latter we must first
        //	explicitly calculate the RGB color itself.

        //	Average the base color with pure white (1,1,1)
        //	to recover the RGB color itself.
        val theColorFactor = (1.0 - lightness) / 0.5
        val theWhiteFactor = 1.0 - theColorFactor
        var theColorR = (theColorFactor * oldBaseR + theWhiteFactor * 1.0)
        var theColorG = (theColorFactor * oldBaseG + theWhiteFactor * 1.0)
        var theColorB = (theColorFactor * oldBaseB + theWhiteFactor * 1.0)

        //	If numerical errors left us with, say, 0.9999999 instead of 1.0000000,
        //	snap to 1.0 exactly.  (This may leave other numerical errors,
        //	for example 0.4999999, uncorrected, but trying to fix them would be messy.)
        if (theColorR > 0.99999) {
            theColorR = 1.0
        }
        if (theColorG > 0.99999) {
            theColorG = 1.0
        }
        if (theColorB > 0.99999) {
            theColorB = 1.0
        }

        //	Note the color's brightness, which by definition is max(R,G,B).
        theNewBrightness = maxOf(theColorR, theColorG, theColorB)

        //	Project the color onto the cube's surface of brightness 1
        //	to get the new base color.
        //	(itsBrightness is at least 1/2, so there's no risk of division by zero.)
        val theFactor = 1.0 / theNewBrightness
        theNewBaseR = theColorR * theFactor
        theNewBaseG = theColorG * theFactor
        theNewBaseB = theColorB * theFactor
    }

    //	If numerical errors left us with, say, 0.9999999 instead of 1.0000000,
    //	snap to 1.0 exactly.  (This may leave other numerical errors,
    //	for example 0.4999999, uncorrected, but trying to fix them would be messy.)
    if (theNewBaseR > 0.99999) {
        theNewBaseR = 1.0
    }
    if (theNewBaseG > 0.99999) {
        theNewBaseG = 1.0
    }
    if (theNewBaseB > 0.99999) {
        theNewBaseB = 1.0
    }

    return FactoredColor(theNewBaseR, theNewBaseG, theNewBaseB, theNewBrightness)
}

//	For use when converting from KaleidoPaint File Format 1.2 to 1.3.
fun convertColorFromGammaEncodedToLinear(
    oldBaseR: Double, // 	the old "base color"
    oldBaseG: Double,
    oldBaseB: Double,
    //	assume a == 1  (that is, opacity α == 1)
    oldBrightness: Double,
): FactoredColor { //	returns new (R, G, B, brightness)

    //	This function is used only when converting from File Format 1.2 to File Format 1.3.

    //	Multiply by the brightness to get the color that would have been
    //	written into the frame buffer in older versions of KaleidoPaint.
    val theGammaEncodedR = oldBaseR * oldBrightness
    val theGammaEncodedG = oldBaseG * oldBrightness
    val theGammaEncodedB = oldBaseB * oldBrightness

    //	Gamma-decode that color, to get the linear color that newer versions of KaleidoPaint
    //	will submit to the frame buffer (with the understanding that Metal will automatically
    //	gamma-encode that submitted color, because KaleidoPaint now uses an _sRGB pixel format).
    val theLinearR = gammaDecode(theGammaEncodedR)
    val theLinearG = gammaDecode(theGammaEncodedG)
    val theLinearB = gammaDecode(theGammaEncodedB)

    //	Factor the linear color into a maximally bright base color along with a brightness.
    val theMaxComponent = maxOf(theLinearR, theLinearG, theLinearB)
    val theLinearBaseR: Double
    val theLinearBaseG: Double
    val theLinearBaseB: Double
    if (theMaxComponent > 0.0) {
        val theFactor = 1.0 / theMaxComponent
        theLinearBaseR = theLinearR * theFactor
        theLinearBaseG = theLinearG * theFactor
        theLinearBaseB = theLinearB * theFactor
    } else { //	the color is black
        //	Let the base color be neutral white
        theLinearBaseR = 1.0
        theLinearBaseG = 1.0
        theLinearBaseB = 1.0
    }

    return FactoredColor(theLinearBaseR, theLinearBaseG, theLinearBaseB, theMaxComponent)
}

//	For use when converting from KaleidoPaint File Format 1.3 to 1.4.
fun convertColorFromSRGBLinearToP3Linear(
    oldBaseR: Double, // 	the old "base color"
    oldBaseG: Double,
    oldBaseB: Double,
    //	assume a == 1  (that is, opacity α == 1)
    oldBrightness: Double,
): FactoredColor { //	returns new (R, G, B, brightness)

    //	Multiply the base color times the brightness to get
    //	the color of interest in Linear sRGB coordinates.
    //	(In principle this would work even with Extended sRGB coordinates,
    //	although in practice previous versions of KaleidoPaint
    //	have supported only non-extended sRGB.)
    val theLinearSRGBColor = Double3(oldBaseR, oldBaseG, oldBaseB) * oldBrightness

    //	Convert to Linear Display P3 coordinates.
    val theLinearP3Color = gSRGBtoP3 * theLinearSRGBColor

    //	Factor theLinearP3Color into a maximally bright base color along with a brightness.
    val theNewBrightness = maxOf(theLinearP3Color[0], theLinearP3Color[1], theLinearP3Color[2])
    val theNewBase =
        (if (theNewBrightness > 0.0)

            //	color is non-black
            theLinearP3Color / theNewBrightness
        else

        //	color is black, use white as netural base color
        Double3(1.0, 1.0, 1.0))

    return FactoredColor(theNewBase[0], theNewBase[1], theNewBase[2], theNewBrightness)
}
