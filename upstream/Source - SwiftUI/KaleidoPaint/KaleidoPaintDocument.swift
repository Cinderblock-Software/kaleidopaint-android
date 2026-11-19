//	KaleidoPaintDocument.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
	nonisolated static var kaleidoPaint: UTType {
		UTType(exportedAs: "org.geometrygames.KaleidoPaint-mobile.drawing")
	}
}

enum TouchMode: CaseIterable, Identifiable {
	
	case draw
	case edit

	var id: Self {self}

	//	For SwiftUI this should really return a LocalizedStringKey,
	//	but non-SwiftUI code doesn't know about LocalizedStringKeys
	//	so we return a plain String and let the caller convert it as needed.
	func localizedNameKey() -> String {
		switch self {
		case .draw: return "DrawMode"	//	translates as "Draw"
		case .edit: return "EditMode"	//	translates as "Edit"
		}
	}
}

enum PanelType {

	case noPanel
	case brushColor
	case fillColor
	case brushThickness
	case smoothingTolerance
	case backgroundColor
	case symmetry
	case export
	case helpMenuPanel
	case helpQuickStart
	case helpEditor
	case helpTutorials
	case helpImageGallery
	case helpContact
	case translators

	var wantsSemiTransparentToolbarsInNarrowLayouts: Bool {
		switch self {
		case .noPanel:				return false
		case .brushColor:			return false
		case .fillColor:			return false
		case .brushThickness:		return true
		case .smoothingTolerance:	return true
		case .backgroundColor:		return true
		case .symmetry:				return true
		case .export:				return true
		case .helpMenuPanel:		return true
		case .helpQuickStart:		return false
		case .helpEditor:			return true
		case .helpTutorials:		return true
		case .helpImageGallery:		return true
		case .helpContact:			return true
		case .translators:			return true
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
let gDefaultThickness = 0.03125	//	in unit cell coordinates

//	The current version of KaleidoPaint uses a fixed unit cell resolution
//	of 11, which strikes a good balance between image quality and speed.
//
//		2¹¹ × 2¹¹ = 2048 × 2048 pixels
//
let log2UnitCellResolution: Int = 11


@Observable final class KaleidoPaintDocument: GeometryGamesUpdatable, ReferenceFileDocument {

// MARK: -
// MARK: Model data

	//	Note that GeometryGamesUpdatable.changeCount has nothing to do
	//	with saving changes; SwiftUI saves changes iff there are items
	//	on the undo stack.
	
	var itsWallpaperGroup: WallpaperGroup = {
		let theRawValue = UserDefaults.standard.string(forKey: "default symmetry group") ?? "○"
		return WallpaperGroup(rawValue: theRawValue) ?? .wpgO
	}()

	var itsUnitCellPlacement: UnitCellPlacement = {
		let theRawValue = UserDefaults.standard.string(forKey: "default symmetry group") ?? "○"
		let theWallpaperGroup = WallpaperGroup(rawValue: theRawValue) ?? .wpgO
		return UnitCellPlacement(defaultForWallpaperGroup: theWallpaperGroup)
	}()
	func mutateUnitCellPlacement(
		corner: SIMD2<Double>,
		translationsMultiplier: Double
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
	var itsRestorableUnitCellPlacement: UnitCellPlacement?
	
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
	var itsBrushColor: LinearDisplayP3Color
		= LinearDisplayP3Color(r: 1.00, g: 0.00, b: 0.00, a: 1.0)

	//	What color should newly created flood fills have?
	var itsFillColor: LinearDisplayP3Color
		= LinearDisplayP3Color(r: 0.25, g: 0.00, b: 1.00, a: 1.0)

	//	What color should the background have?
	var itsBackgroundColor: LinearDisplayP3Color
		= LinearDisplayP3Color(r: 0.37636709, g: 0.75232202, b: 0.95496619, a: 1.0)

	//	What thickness should newly created dots and curves have?
	//
	//		Note:  On the one hand, we set a default brush thickness
	//		that's proportional to the quotient orbifold's linear dimensions.
	//		On the other hand, if the user later changes the wallpaper group,
	//		we keep the same brush thickness — we don't rescale it
	//		for the new group.
	//
	var itsBrushThickness: Double = { 	//	in unit cell coordinates
		let theRawValue = UserDefaults.standard.string(forKey: "default symmetry group") ?? "○"
		let theWallpaperGroup = WallpaperGroup(rawValue: theRawValue) ?? .wpgO
		return gDefaultThickness / sqrt(Double(theWallpaperGroup.torusGroup.itsElements.count))
	}()

	//	How vigorously should KaleidoPaint smooth newly created curves,
	//	to eliminate any untentional little wobbles that the user's
	//	shaky finger might have produced?
	//
	//		The comments in ramerDouglasPeucker() and
	//		ramerDouglasPeuckerInteriorNodes() explain
	//		itsSmoothingTolerance's geometrical significance.
	//
	var itsSmoothingTolerance: Double = 0.0085	//	medium

	//	Show mirror lines, gyration points and glide axes?
	var itsShowSingularitiesFlag: Bool = true
	
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
	var itsColorBySymmetryFlag: Bool = false

	//	The user may lock the drawing's content to prevent accidental changes.
	var itsContentIsLocked: Bool = false

	var itsElements: [DrawingElement] = []

	//	When the user taps a control handle in TouchToEdit mode,
	//	remember the selected control point along with some other
	//	useful information about the hit.  itsControlHandleHit
	//	will be non-nil only while a drag is in progress or,
	//	in the case that the user taps a control point,
	//	while the requested popup menu is visible.
	//	Beyond that, there is no notion of a selected element.
	var itsControlHandleHit: ControlHandleHit?

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
	var itsBaseDrawingTextureFullRedrawRequestCount: Int = 1	//	request initial redraw
	var itsBaseDrawingTextureLastElementRequestCount: Int = 0
	var itsCurveInProgressTextureRedrawRequestCount: Int = 1	//	request initial redraw
	var itsSingularitiesTextureRedrawRequestCount: Int = 1		//	request initial redraw
	var itsCompositeTextureRedrawRequestCount: Int = 1			//	request initial redraw
	
	//	While the user is drawing a new curve,
	//	we'll keep track of it separately from the rest
	//	of the drawing, and render it in its own texture
	//	(in effect in its own layer) so that we don't
	//	have to re-render the rest of the drawing for every frame.
	var itsCurveInProgress: Curve? = nil	//	= NULL when no curve is in progress

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
	var itsCurveInProgressTouchOffset: SIMD2<Int> = SIMD2<Int>.zero	//	(-18,-7) in the example above
	var itsCurveInProgressValidBasepoints: Set<SIMD2<Int>> = Set()
	var itsCurveInProgressAcceptsNewPoints: Bool = false

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
	//		https://stackoverflow.com/questions/60647857/undomanagers-canundo-property-not-updating-in-swiftui
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
	var itsUndoManager: UndoManager?	//	KaleidoPaintContentView's body() will set this.
	var itsUndoRedoCount: Int = 0

	var itsTouchMode: TouchMode = .draw

	var itsGestureRecognizerDelegate = KaleidoPaintGestureRecognizerDelegate()

// MARK: -
// MARK: Initialization

	//	The ReferenceFileDocument protocol is defined in terms of an
	//
	//		associatedtype Snapshot
	//
	//	KaleidoPaint drawings get saved as textual descriptions,
	//	so we let this associatedtype be a String.
	//
	typealias Snapshot = String
	nonisolated static var readableContentTypes: [UTType] { [.kaleidoPaint] }

	//	decodeFileFormat() should, I hope, have no problems
	//	decoding the files we've written ourselves.
	//	But if the user creates a .kaleidoPaint file externally
	//	and adds it to our file folder, then it would be nice
	//	to clearly explain any error we might find in it.
	//	For an example of how to show an error alert, see
	//
	//		https://augmentedcode.io/2020/03/01/alert-and-localizederror-in-swiftui/
	//
	//	Alas... trying to show an error during an init()
	//	seems somehow risky, so I'm not going to attempt this just yet.
	//	Maybe some other day.  For now, just let the error propagate
	//	up the line (at which point the SwiftUI will silently
	//	abort opening the drawing).
	
	//	Initializes a KaleidoPaintDocument for an empty drawing
	nonisolated init() {

		//	Whenever the user opens a drawing,
		//	SwiftUI first calls this init() to open
		//	an empty drawing, then immediately thereafter
		//	calls init(configuration: ReadConfiguration)
		//	to open the drawing that the user requested.
		//	Presumably it uses the empty drawing to put
		//	a window up as quickly as possible, just
		//	in case the requested drawing is slow to load.
		
		//	This document's properties' default values
		//	already define an unlocked empty drawing.
		//	No further initialization is need.
	}

	//	Initializes a KaleidoPaintDocument when opening a file.
	//
	//	----------------------------
	//
	//	ReferenceFileDocument's nonisolated protocol
	//	conformance will be an issue in Swift 6.
	//
	//	On the one hand, even though we're modifying mutable variables,
	//	there's no danger of a data race because as long as we're
	//	still in the init(), no other code knows about this instance
	//	of MyDocument (and we avoid starting Tasks that could
	//	access our variables).
	//
	//	On the other hand, there's currently no way to tell
	//	the Swift 6 compiler that. So as soon as we uncomment
	//	the 'nonisolated' keyword here, Swift 6 will complain
	//	about modifying isolated state in a nonisolated context.
	//
//	nonisolated
	init(configuration: ReadConfiguration) throws {
	
		guard let theDrawingAsUTF8EncodedData = configuration.file.regularFileContents,
			  let theDrawingAsText = String(data: theDrawingAsUTF8EncodedData, encoding: .utf8)
		else {
			throw CocoaError(.fileReadCorruptFile)
		}
		
		do {
			try decodeFileFormat(theDrawingAsText)
		} catch {
			assertionFailure("Error in decodeFileFormat: \(error)")	//	See comment above re error reporting
			throw error
		}
	}

	//	Initializes a KaleidoPaintDocument for use when creating a thumbnail
	init(drawingAsText: String) throws {

		do {
			try decodeFileFormat(drawingAsText)
		} catch {
			assertionFailure("Error in decodeFileFormat: \(error)")	//	See comment above re error reporting
			throw error
		}
	}

// MARK: -
// MARK: Saving to file

	//	Apple's introduction to document-based apps at
	//
	//		https://developer.apple.com/documentation/swiftui/building_a_document-based_app_with_swiftui
	//
	//	says
	//
	//		Implementing undo management also alerts SwiftUI
	//		when the document changes.
	//
	//	In other words, when the app goes into the background
	//	(and at other times too, when nothing else is happening),
	//	SwiftUI saves the document iff there are unsaved changes
	//	on the undo stack.
	//
	//	----------------------------
	//
	//	ReferenceFileDocument's nonisolated protocol
	//	conformance will be an issue in Swift 6.
	//
	//	On the one hand, Apple's documentation for snapshot() says
	//
	//		SwiftUI prevents document edits during the snapshot
	//		operation to ensure that the model state remains coherent.
	//		After the call completes, SwiftUI reenables edits,
	//		and then calls the fileWrapper(snapshot:configuration:) method,
	//		where you serialize the snapshot and store it to a file.
	//
	//	So even though we're modifying mutable variables,
	//	there's no danger of a data race.
	//
	//	On the other hand, there's currently no way to tell
	//	the Swift 6 compiler that. So as soon as we uncomment
	//	the 'nonisolated' keyword here, Swift 6 will complain
	//	about modifying isolated state in a nonisolated context.
	//
//	nonisolated
	func snapshot(contentType: UTType) throws -> String {

		let theDrawingAsText = encodeFileFormat()
		
		return theDrawingAsText
	}

	nonisolated func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {

		//	Converting a Swift String to UTF-8 will always succeed,
		//	so it's safe to force unwrap snapshot.data()'s optional return value.
		//	The reason the return value is an optional is that
		//	if we were converting to, say, ASCII or Latin-1,
		//	the conversion would fail when given, say, Cyrillic letters
		//	or Chinese characters.
		//
		let theDrawingAsUTF8EncodedData = snapshot.data(using: .utf8)!

		return FileWrapper.init(regularFileWithContents: theDrawingAsUTF8EncodedData)
	}


// MARK: -
// MARK: File encoding

	enum KaleidoPaintFileEncodingError: Error {
		case fileFormatError(reason: String)
	}
	
	let theCurrentMajorVersionNumber = 1
	let theCurrentMinorVersionNumber = 10

	func encodeFileFormat() -> String {

		var theDrawingAsText = ""
	
		theDrawingAsText.append("KaleidoPaint Drawing\n")
		theDrawingAsText.append(String(format:
			"format %d.%d\n",
			theCurrentMajorVersionNumber,
			theCurrentMinorVersionNumber))
		theDrawingAsText.append("\n")

		theDrawingAsText.append(
			"wallpaper group "
			+ itsWallpaperGroup.rawValue
			+ "\n")

		theDrawingAsText.append(String(format:
			"unit cell placement\n\t%20.16lf %20.16lf\n\t%20.16lf %20.16lf\n\t%20.16lf %20.16lf\n",
			itsUnitCellPlacement.itsCorner[0],
			itsUnitCellPlacement.itsCorner[1],
			itsUnitCellPlacement.itsTranslations[0][0],
			itsUnitCellPlacement.itsTranslations[0][1],
			itsUnitCellPlacement.itsTranslations[1][0],
			itsUnitCellPlacement.itsTranslations[1][1]))

		//	We could define a new version of the KaleidoPaint file format
		//	that omits the log2 unit cell resolution, but changing
		//	file formats is a pain and it's not out of the question
		//	that we'd someday want to support a larger resolution.
		//	So let's leave the file format as it is, and simply
		//	write the current fixed resolution (11) into the file.
		theDrawingAsText.append(String(format:
			"log2 unit cell resolution %d\n", 11))

		theDrawingAsText.append(String(format:
			"background color %12.8f %12.8f %12.8f %12.8f\n",
			itsBackgroundColor.r,
			itsBackgroundColor.g,
			itsBackgroundColor.b,
			itsBackgroundColor.a))	//	= 1.0
	
		theDrawingAsText.append(String(format:
			"brush color      %12.8f %12.8f %12.8f %12.8f\n",
			itsBrushColor.r,
			itsBrushColor.g,
			itsBrushColor.b,
			itsBrushColor.a))	//	= 1.0
	
		theDrawingAsText.append(String(format:
			"fill color       %12.8f %12.8f %12.8f %12.8f\n",
			itsFillColor.r,
			itsFillColor.g,
			itsFillColor.b,
			itsFillColor.a))	//	= 1.0

		theDrawingAsText.append(String(format:
			"brush thickness  %20.16lf\n",
			itsBrushThickness))

		theDrawingAsText.append(String(format:
			"smoothing tolerance  %20.16lf\n",
			itsSmoothingTolerance))
	
		theDrawingAsText.append("show singularities "
			+ (itsShowSingularitiesFlag ? "true" : "false")
			+ "\n")
	
		theDrawingAsText.append("color by symmetry  "
			+ (itsColorBySymmetryFlag ? "true" : "false")
			+ "\n")
	
		theDrawingAsText.append("content is locked  "
								+ (itsContentIsLocked ? "true" : "false")
								+ "\n")
	
		theDrawingAsText.append("\n")
		theDrawingAsText.append("elements\n")
		theDrawingAsText.append("\n")
		
		let theColorFormat = "\tcolor     %12.8f %12.8f %12.8f %12.8f\n"
	
		for theElement in itsElements {
		
			//	Is theElement a Dot?
			if let theDot = theElement as? Dot {
			
				theDrawingAsText.append("dot\n")

				theDrawingAsText.append(String(format:
					theColorFormat,
					theDot.itsColor.r,
					theDot.itsColor.g,
					theDot.itsColor.b,
					theDot.itsColor.a))

				theDrawingAsText.append(String(format:
					"\tcenter    %20.16lf %20.16lf\n",
					theDot.itsCenter[0],
					theDot.itsCenter[1]))

				theDrawingAsText.append(String(format:
					"\tdiameter  %20.16lf\n",
					theDot.itsThickness))
			}
		
			//	Is theElement a Curve?
			if let theCurve = theElement as? Curve {
			
				theDrawingAsText.append("curve\n")

				theDrawingAsText.append(String(format:
					theColorFormat,
					theCurve.itsColor.r,
					theCurve.itsColor.g,
					theCurve.itsColor.b,
					theCurve.itsColor.a))
		
				theDrawingAsText.append(String(format:
					"\tthickness %20.16lf\n",
					theCurve.itsThickness))

				for theNode in theCurve.itsSpline.itsNodes {
				
					theDrawingAsText.append(
						String(format:
							"\tnode      %12.8lf %12.8lf   ",
							theNode.itsNodeLocation[0],
							theNode.itsNodeLocation[1])
					  + theNode.itsNodeType.rawValue
					  + "\n"
					)
				}
			}
		
			//	Is theElement a Fill?
			if let theFill = theElement as? Fill {
			
				theDrawingAsText.append("fill\n")

				theDrawingAsText.append(String(format:
					theColorFormat,
					theFill.itsColor.r,
					theFill.itsColor.g,
					theFill.itsColor.b,
					theFill.itsColor.a))
		
				theDrawingAsText.append(String(format:
					"\tfillPoint %20.16lf %20.16lf\n",
					theFill.itsFillPoint[0],
					theFill.itsFillPoint[1]))
			}
		
			theDrawingAsText.append("\tno-more-properties\n")
			theDrawingAsText.append("\n")
		}
	
		theDrawingAsText.append("no-more-elements\n")

		return theDrawingAsText
	}

	func decodeFileFormat(
		_ drawingAsText: String
	) throws {
	
		//
		//	Split the drawingAsText String into tokens, separated by white space.
		//
		let theRawTokens = drawingAsText.components(separatedBy: .whitespacesAndNewlines)
		let t = theRawTokens.filter{ $0.count > 0 }	//	't' = "tokens"
		let theNumTokens = t.count
		if theNumTokens < 4 {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "drawing file is impossibly short - fewer than 4 tokens")
		}

		//
		//	Read the file header.
		//
	
		if  t[0] != "KaleidoPaint" || t[1] != "Drawing"
		 || t[2] != "format" {
			throw KaleidoPaintFileEncodingError.fileFormatError(reason: "invalid header format")
		}

		let theVersionTokens = t[3].split(separator: ".")
		guard let theFileFormatMajorVersionNumber = Int(theVersionTokens[0]) else {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "unparsable major version number")
		}
		guard let theFileFormatMinorVersionNumber = Int(theVersionTokens[1]) else {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "unparsable minor version number")
		}
		//	We'll need to be more careful with version number validation
		//	if we ever move to format 2.x.  For now, with 1.x only,
		//	the following will do the job.
		if theFileFormatMajorVersionNumber != theFileFormatMajorVersionNumber
		|| theFileFormatMinorVersionNumber < 0
		|| theFileFormatMinorVersionNumber > theFileFormatMinorVersionNumber {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "Invalid drawing-file format version")
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
		let theColorsNeedLightnessToBrightnessConversion =
			(	theFileFormatMajorVersionNumber == 1
			 && theFileFormatMinorVersionNumber <= 1)
	
		//	Version 1.2 -> 1.3
		//
		let theColorsNeedGammaEncodedToLinearConversion =
			(	theFileFormatMajorVersionNumber == 1
			 && theFileFormatMinorVersionNumber <= 2)
	
		//	Version 1.3 -> 1.4
		//
		let theColorsNeedSRGBtoP3Conversion =
			(	theFileFormatMajorVersionNumber == 1
			 && theFileFormatMinorVersionNumber <= 3)
	
		//	Version 1.4 -> 1.5
		//
		let theColorsNeedFactoredToUnfactoredConversion =
			(	theFileFormatMajorVersionNumber == 1
			 && theFileFormatMinorVersionNumber <= 4)

		//	Version 1.5 -> 1.6
		//
		let theWallpaperGroupIsInOldFormat =
			(	theFileFormatMajorVersionNumber == 1
			 && theFileFormatMinorVersionNumber <= 5)

		//	Version 1.6 -> 1.7
		//
		let thePropertiesNeedUpdating =
			(	theFileFormatMajorVersionNumber == 1
			 && theFileFormatMinorVersionNumber <= 6)


		//	In file format version 1.4 and earlier,
		//	the background color and the brush color each required
		//	a token for the divider "|" and a token for the brightness.
		let theMinNumTokens = (theColorsNeedFactoredToUnfactoredConversion ? 48 : 44)
		if theNumTokens < theMinNumTokens {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "drawing file is impossibly short - even an empty drawing must contain \(theMinNumTokens) tokens")
		}


		//	Read the global information.

		if  t[4] != "wallpaper" || t[5] != "group" {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "'wallpaper group' not found at expected position")
		}
		let theWallpaperGroupRawValue: String
		if theWallpaperGroupIsInOldFormat {
		
			//	We're reading file format 1.5 or earlier, which
			//	stored the wallpaper group as an integer ∈ {0, … , 16}.
			let theLegacyIndexingScheme = ["○", "2222", "333", "442", "632", "*2222", "*333", "*442", "*632", "22*", "2*22", "3*3", "4*2", "**", "22×", "*×", "××"]

			guard let theWallpaperGroupAsInt = Int(t[6]) else {
				throw KaleidoPaintFileEncodingError.fileFormatError(
					reason: "unparsable legacy wallpaper group number")
			}
			if theWallpaperGroupAsInt < 0
			|| theWallpaperGroupAsInt >= theLegacyIndexingScheme.count {
				throw KaleidoPaintFileEncodingError.fileFormatError(
					reason: "invalid legacy wallpaper group number")
			}
			theWallpaperGroupRawValue = theLegacyIndexingScheme[theWallpaperGroupAsInt]
		
		} else {
			//	We're reading file format 1.6 or later, which
			//	stores the wallpaper group as a string
			//	containing the group's name in orbifold notation
			theWallpaperGroupRawValue = t[6]
		}
		guard let theWallpaperGroup = WallpaperGroup(rawValue: theWallpaperGroupRawValue) else {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "invalid wallpaper group name (orbifold notation expected, ∈ {'○', '2222', '333', '442', '632', '*2222', '*333', '*442', '*632', '22*', '2*22', '3*3', '4*2', '**', '22×', '*×', '××'})")
		}
		itsWallpaperGroup = theWallpaperGroup
	
		if  t[7] != "unit" || t[8] != "cell" || t[9] != "placement" {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "'unit cell placement' not found at expected position")
		}
		guard
			let theCorner0 = Double(t[10]),
			let theCorner1 = Double(t[11]),
			let theTranslations00 = Double(t[12]),
			let theTranslations01 = Double(t[13]),
			let theTranslations10 = Double(t[14]),
			let theTranslations11 = Double(t[15])
		else {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "invalid data for 'unit cell placement'")
		}
		itsUnitCellPlacement.itsCorner[0] = theCorner0
		itsUnitCellPlacement.itsCorner[1] = theCorner1
		itsUnitCellPlacement.itsTranslations[0][0] = theTranslations00
		itsUnitCellPlacement.itsTranslations[0][1] = theTranslations01
		itsUnitCellPlacement.itsTranslations[1][0] = theTranslations10
		itsUnitCellPlacement.itsTranslations[1][1] = theTranslations11
	
		var theTokenIndex = 16

		//	The current version of KaleidoPaint uses a fixed resolution (11),
		//	but for simplicity the file format still retains a field
		//	for the "log2 unit cell resolution", which we skip over
		//	when reading the file.
		if theFileFormatMajorVersionNumber > 1
		|| (	theFileFormatMajorVersionNumber == 1
			 && theFileFormatMinorVersionNumber >= 10) {

			if  t[theTokenIndex + 0] != "log2"
			 || t[theTokenIndex + 1] != "unit"
			 || t[theTokenIndex + 2] != "cell"
			 || t[theTokenIndex + 3] != "resolution" {
				throw KaleidoPaintFileEncodingError.fileFormatError(
					reason: "'log2 unit cell resolution' not found at expected position")
			}
			
//			guard let theDecodedLog2UnitCellResolution = Int(t[theTokenIndex + 4]) else {
//				throw KaleidoPaintFileEncodingError.fileFormatError(
//					reason: "invalid data for 'log2 unit cell resolution'")
//			}
			
			theTokenIndex += 5
			
		} else {	//	file format 1.9 or earlier

			//	Those older file formats didn't include
			//	the "log2 unit cell resolution".
		}

		func readOneLinearDisplayP3Color() throws -> LinearDisplayP3Color {
	
			guard
				var r = Double(t[theTokenIndex + 0]),
				var g = Double(t[theTokenIndex + 1]),
				var b = Double(t[theTokenIndex + 2]),
				let a = Double(t[theTokenIndex + 3])	//	= 1.0
			else {
				throw KaleidoPaintFileEncodingError.fileFormatError(
					reason: "invalid data for color")
			}
			if a != 1.0 {
				throw KaleidoPaintFileEncodingError.fileFormatError(
					reason: "color opacity must be 1.0")
			}

			if theColorsNeedFactoredToUnfactoredConversion {	//	file format 1.4 or earlier

				if t[theTokenIndex + 4] != "|" {
					throw KaleidoPaintFileEncodingError.fileFormatError(
						reason: "color separator bar '|' not found at expected position")
				}

				guard
					var theBrightness = Double(t[theTokenIndex + 5])	//	in version 1.1, this is "lightness"
				else {
					throw KaleidoPaintFileEncodingError.fileFormatError(
						reason: "invalid data for legacy 'background color' brightness")
				}

				if theColorsNeedLightnessToBrightnessConversion {
					(r, g, b, theBrightness)
						= convertColorFromHSLtoHSB(r, g, b, theBrightness)
				}
				if theColorsNeedGammaEncodedToLinearConversion {
					(r, g, b, theBrightness)
						= convertColorFromGammaEncodedToLinear(r, g, b, theBrightness)
				}
				if theColorsNeedSRGBtoP3Conversion {
					(r, g, b, theBrightness)
						= convertColorFromSRGBLinearToP3Linear(r, g, b, theBrightness)
				}
			
				r *= theBrightness
				g *= theBrightness
				b *= theBrightness

				theTokenIndex += 6
			}
			else {	//	file format is version 1.5 or later
				theTokenIndex += 4
			}
		
			let theLinearDisplayP3Color = LinearDisplayP3Color(r: r, g: g, b: b, a: a)
		
			return theLinearDisplayP3Color
		}

		if  t[theTokenIndex + 0] != "background" || t[theTokenIndex + 1] != "color" {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "'background color' not found at expected position")
		}
		theTokenIndex += 2
		itsBackgroundColor = try readOneLinearDisplayP3Color()
	
		if  t[theTokenIndex] != "brush" || t[theTokenIndex + 1] != "color" {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "'brush color' not found at expected position")
		}
		theTokenIndex += 2
		itsBrushColor = try readOneLinearDisplayP3Color()

		if theFileFormatMajorVersionNumber > 1
		|| (	theFileFormatMajorVersionNumber == 1
			 && theFileFormatMinorVersionNumber >= 9) {

			if  t[theTokenIndex] != "fill" || t[theTokenIndex + 1] != "color" {
				throw KaleidoPaintFileEncodingError.fileFormatError(
					reason: "'fill color' not found at expected position")
			}
			theTokenIndex += 2
			itsFillColor = try readOneLinearDisplayP3Color()
		}

		if  t[theTokenIndex] != "brush" || t[theTokenIndex + 1] != "thickness" {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "'brush thickness' not found at expected position")
		}
		guard let theBrushThickness = Double(t[theTokenIndex + 2]) else {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "invalid data for 'brush thickness'")
		}
		itsBrushThickness = (
						
			thePropertiesNeedUpdating ?
				//	Version 1.6 and earlier interpreted "thickness"
				//		as a half-thickness, so double it
				2.0 * theBrushThickness :
				theBrushThickness
		)
		theTokenIndex += 3

		if theFileFormatMajorVersionNumber > 1
		|| (	theFileFormatMajorVersionNumber == 1
			 && theFileFormatMinorVersionNumber >= 8) {

			if  t[theTokenIndex] != "smoothing"
			|| (   t[theTokenIndex + 1] != "tolerance"
					//	The term "smoothing factor" was used briefly
					//	while KaleidoPaint 3.0 was in beta,
					//	so it might still be present in some
					//	of Francine's, Geneviève's and/or my drawings.
				&& t[theTokenIndex + 1] != "factor") {
				throw KaleidoPaintFileEncodingError.fileFormatError(
					reason: "'smoothing tolerance' not found at expected position")
			}
			guard let theSmoothingTolerance = Double(t[theTokenIndex + 2]) else {
				throw KaleidoPaintFileEncodingError.fileFormatError(
					reason: "invalid data for 'smoothing tolerance'")
			}
			itsSmoothingTolerance = theSmoothingTolerance
			theTokenIndex += 3
		}
		
		if  t[theTokenIndex] != "show" || t[theTokenIndex + 1] != "singularities" {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "'show singularities' not found at expected position")
		}
		if t[theTokenIndex + 2] == "false" {
			itsShowSingularitiesFlag = false
		} else
		if t[theTokenIndex + 2] == "true" {
			itsShowSingularitiesFlag = true
		} else {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "invalid data for 'show singularities' (must be 'false' or 'true')")
		}
		theTokenIndex += 3

		if  t[theTokenIndex] != "color" || t[theTokenIndex + 1] != "by" || t[theTokenIndex + 2] != "symmetry" {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "'color by symmetry' not found at expected position")
		}
		if t[theTokenIndex + 3] == "false" {
			itsColorBySymmetryFlag = false
		} else
		if t[theTokenIndex + 3] == "true" {
			itsColorBySymmetryFlag = true
		} else {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "invalid data for 'show singularities' (must be 'false' or 'true')")
		}
		theTokenIndex += 4
	
		if theFileFormatMajorVersionNumber > 1
		|| (	theFileFormatMajorVersionNumber == 1
			 && theFileFormatMinorVersionNumber >= 1) {

			if  t[theTokenIndex] != "content" || t[theTokenIndex + 1] != "is" || t[theTokenIndex + 2] != "locked" {
				throw KaleidoPaintFileEncodingError.fileFormatError(
					reason: "'content is locked' not found at expected position")
			}
			if t[theTokenIndex + 3] == "false" {
				itsContentIsLocked = false
			} else
			if t[theTokenIndex + 3] == "true" {
				itsContentIsLocked = true
			} else {
				throw KaleidoPaintFileEncodingError.fileFormatError(
					reason: "invalid data for 'content is locked' (must be 'false' or 'true')")
			}
			theTokenIndex += 4
		}
		else
		{
			itsContentIsLocked = false	//	legacy files assumed unlocked
		}
	
		//	Read the flexible list of drawing elements.
	
		//	The list must begin with an "elements" label
		//	and end with a "no-more-elements" label.
		if t[theTokenIndex] != "elements" {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "'elements' not found at expected position")
		}
		theTokenIndex += 1
		if t[theNumTokens - 1] != "no-more-elements" {
			throw KaleidoPaintFileEncodingError.fileFormatError(
				reason: "'no-more-elements' not found at end of file")
		}

		//	The list may continue with any sequence of dots, curves and fills,
		//	until it finishes with the label "no-more-elements".
		//
		//		Note:  We checked (immediately above) that
		//		a "no-more-elements" label appears at the end of the file.
		//		Its presence ensures that the loops below will never
		//		try to read past the end of the array t[].
		//
		while theTokenIndex < theNumTokens - 1 {	//	t[theNumTokens - 1] == "no-more-elements"
		
			let theElementType = t[theTokenIndex]
			theTokenIndex += 1
			
			if theElementType == "dot" {
			
				let theDot = Dot()

				//	Read theDot's properties, which may appear in any order.
				while true {
				
					let thePropertyType = t[theTokenIndex]
					theTokenIndex += 1
				
					if thePropertyType == "no-more-properties" {
						break
					}
				
					switch thePropertyType {
					
					case "color":

						theDot.itsColor = try readOneLinearDisplayP3Color()

					case "location",	//	file format version ≤ 1.6
						 "center":		//	file format version ≥ 1.7

						guard
							let theDotCenter0 = Double(t[theTokenIndex + 0]),
							let theDotCenter1 = Double(t[theTokenIndex + 1])
						else {
							throw KaleidoPaintFileEncodingError.fileFormatError(
								reason: "invalid data for dot center")
						}
						theTokenIndex += 2
						theDot.itsCenter = SIMD2<Double>(
							theDotCenter0, theDotCenter1)

					case "thickness":	//	file format version ≤ 1.6
										//	  interpreted "thickness" as a radius

						guard let theDotRadius = Double(t[theTokenIndex]) else {
							throw KaleidoPaintFileEncodingError.fileFormatError(
								reason: "invalid data for dot radius")
						}
						theTokenIndex += 1
						theDot.itsThickness = 2.0 * theDotRadius

					case "diameter":	//	file format version ≥ 1.7

						guard let theDotDiameter = Double(t[theTokenIndex]) else {
							throw KaleidoPaintFileEncodingError.fileFormatError(
								reason: "invalid data for dot diameter")
						}
						theTokenIndex += 1
						theDot.itsThickness = theDotDiameter

					default:
						throw KaleidoPaintFileEncodingError.fileFormatError(
							reason: "invalid property type for dot (must be 'color', 'center' or 'diameter')")
					}
				}

				itsElements.append(theDot)

			} else if theElementType == "curve" {
			
				let theCurve = Curve()

				//	Read theCurve's properties, which may appear in any order,
				//	except that the file must list the SplineNodes
				//	in the order in which they appear on the curve itself.
				//
				while true {
				
					let thePropertyType = t[theTokenIndex]
					theTokenIndex += 1
				
					if thePropertyType == "no-more-properties" {
						break
					}
				
					switch thePropertyType {
					
					case "color":

						theCurve.itsColor = try readOneLinearDisplayP3Color()

					case "thickness":

						guard let theCurveThickness = Double(t[theTokenIndex]) else {
							throw KaleidoPaintFileEncodingError.fileFormatError(
								reason: "invalid data for curve thickness")
						}
						theTokenIndex += 1
						theCurve.itsThickness = (
						
							thePropertiesNeedUpdating ?
							
								//	Version 1.6 and earlier interpreted
								//		"thickness" as a half-thickness,
								//		so double it
								2.0 * theCurveThickness :
								
								theCurveThickness
						)

					case "node":

						guard
							let theNodeLocation0 = Double(t[theTokenIndex + 0]),
							let theNodeLocation1 = Double(t[theTokenIndex + 1])
						else {
							throw KaleidoPaintFileEncodingError.fileFormatError(
								reason: "invalid data for spline node location")
						}
						guard let theNodeType
							= SplineNodeType(rawValue: t[theTokenIndex + 2]) else {
						
							throw KaleidoPaintFileEncodingError.fileFormatError(
								reason: "invalid data for spline node type")
						}
						theTokenIndex += 3
						
						let theNode = SplineNode(
							location: SIMD2<Double> (
								theNodeLocation0,
								theNodeLocation1
							),
							type: theNodeType)
						
						theCurve.itsSpline.append(theNode)
					
					default:
						throw KaleidoPaintFileEncodingError.fileFormatError(
							reason: "invalid property type for curve (must be 'color', 'thickness' or 'node')")
					}
				}
				
				//	Make sure the curve is properly centered in the unit cell.
				//	This check is needed only for older drawings
				//	(KaleidoPaint 3.0.2 and earlier).  Newly created
				//	drawings will all keep the curve centered automatically.
				theCurve.itsSpline.keepCenteredInUnitCell()

				//	Compute the spline parameters.
				theCurve.itsSpline.refreshParameterization()

				itsElements.append(theCurve)

			} else if theElementType == "fill" {
			
				let theFill = Fill()

				//	Read theFill's properties, which may appear in either order.
				//
				while true {
				
					let thePropertyType = t[theTokenIndex]
					theTokenIndex += 1
				
					if thePropertyType == "no-more-properties" {
						break
					}
				
					switch thePropertyType {
					
					case "color":

						theFill.itsColor = try readOneLinearDisplayP3Color()

					case "location",	//	file format version ≤ 1.6
						 "fillPoint":	//	file format version ≥ 1.7

						guard
							let theFillPoint0 = Double(t[theTokenIndex + 0]),
							let theFillPoint1 = Double(t[theTokenIndex + 1])
						else {
							throw KaleidoPaintFileEncodingError.fileFormatError(
								reason: "invalid data for flood fill's fillPoint")
						}
						theTokenIndex += 2
						theFill.itsFillPoint = SIMD2<Double>(
							theFillPoint0, theFillPoint1)
					
					default:
						throw KaleidoPaintFileEncodingError.fileFormatError(
							reason: "invalid property type for flood fill (must be 'color' or 'fillPoint')")
					}
				}

				itsElements.append(theFill)

			} else {
				throw KaleidoPaintFileEncodingError.fileFormatError(
					reason: "invalid drawing element type (must be 'dot', 'curve' or 'fill')")
			}
		}
	}


// MARK: -
// MARK: Animation

	var changeCount: UInt64 = 0
	func updateModel() -> UInt64 {
	
		//	KaleidoPaint uses no independent simulations or animations.
		//	All animations are in response to the user direct input.
				
		return changeCount
	}


// MARK: -
// MARK: Undo/Redo operations

	func changeBackgroundColor(
		to newBackgroundColor: LinearDisplayP3Color
	) {
	
		let theOldBackgroundColor = itsBackgroundColor

		let theOperation = { backgroundColor in
		
			self.itsBackgroundColor = backgroundColor
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theDoOperation   = { theOperation(newBackgroundColor) }
		let theUndoOperation = { theOperation(theOldBackgroundColor) }

		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}
	
	func appendDrawingElement(
		_ drawingElement: DrawingElement
	) {
		//	Calling appendDrawingElement() is slightly more efficient
		//	than calling the general-purpose function changeElementArray().

		let theDoOperation = {
		
			self.itsElements.append(drawingElement)
		
			self.changeCount += 1
			self.itsBaseDrawingTextureLastElementRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theUndoOperation = {
		
			self.itsElements.removeLast()
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}
	
	func moveDot(
		_ dot: Dot,
		from oldPosition: SIMD2<Double>,
		to newPosition: SIMD2<Double>
	) {
	
		let theOperation = { position in
		
			dot.itsCenter = position
			
			self.clearCachedRLERuns(from: dot)
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theDoOperation   = { theOperation(newPosition) }
		let theUndoOperation = { theOperation(oldPosition) }
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}

	func moveSplineNode(
		curve: Curve,
		node: SplineNode,
		from oldPosition: SIMD2<Double>,
		to newPosition: SIMD2<Double>
	) {
	
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
		let theShiftToKeepCentered = curve.itsSpline.computeShiftToKeepCenteredInUnitCell()

		let theDoOperation = {
		
			//	First set the newPosition...
			node.itsNodeLocation = newPosition
			
			//	... then shift the whole curve to keep it centered.
			curve.itsSpline.applyShift(theShiftToKeepCentered)
			
			curve.itsSpline.refreshParameterization()
			self.clearCachedRLERuns(from: curve)
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theUndoOperation = {

			//	First undo the shift...
			curve.itsSpline.applyShift(-theShiftToKeepCentered)
			
			//	... and then set the oldPosition.
			node.itsNodeLocation = oldPosition
			
			curve.itsSpline.refreshParameterization()
			self.clearCachedRLERuns(from: curve)
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}
	
	func moveFill(
		_ fill: Fill,
		from oldPosition: SIMD2<Double>,
		to newPosition: SIMD2<Double>
	) {

		let theOperation = { position in
		
			fill.itsFillPoint = position
			
			self.clearCachedRLERuns(from: fill)
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theDoOperation   = { theOperation(newPosition) }
		let theUndoOperation = { theOperation(oldPosition) }
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}

	func deleteSplineNode(
		curve: Curve,
		node: SplineNode
	) {
		
		let theSpline = curve.itsSpline

		if theSpline.itsNodes.count < 3 {	//	must keep ≥ 2 nodes (caller also checks this)
			assertionFailure("Internal error:  deleteSplineNode() received a spline with fewer than 3 nodes")
			return
		}
		
		guard let theNodeIndex = theSpline.itsNodes.firstIndex(
								where: { aNode in aNode === node }) else {
			assertionFailure("Internal error:  deleteSplineNode() received a node that's not part of the spline")
			return
		}
		let theDeletedNode = theSpline.itsNodes[theNodeIndex]

		let theDoOperation = {
		
			theSpline.itsNodes.remove(at: theNodeIndex)
			theSpline.refreshParameterization()
			self.clearCachedRLERuns(from: curve)
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theUndoOperation = {
		
			theSpline.itsNodes.insert(theDeletedNode, at: theNodeIndex)
			theSpline.refreshParameterization()
			self.clearCachedRLERuns(from: curve)
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}

	func splitSplineNode(
		curve: Curve,
		oldNode: SplineNode,
		newNodeA: SplineNode,
		newNodeB: SplineNode
	) {

		let theSpline = curve.itsSpline

		guard let i = theSpline.itsNodes.firstIndex(where: {node in node === oldNode} ) else {
		
			assertionFailure(
				"Internal error:  splitSplineNode received an oldNode that's not part of the curve")
			
			return
		}

		let theDoOperation = {
		
			curve.itsSpline.itsNodes.replaceSubrange(i ... i, with: [newNodeA, newNodeB])
			theSpline.refreshParameterization()
			self.clearCachedRLERuns(from: curve)
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theUndoOperation = {
		
			curve.itsSpline.itsNodes.replaceSubrange(i ... i+1, with: [oldNode])
			theSpline.refreshParameterization()
			self.clearCachedRLERuns(from: curve)
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}
	
	func changeSplineNodeType(
		curve: Curve,
		node: SplineNode,
		from oldType: SplineNodeType,
		to newType: SplineNodeType
	) {

		let theSpline = curve.itsSpline

		let theOperation = { nodeType in
		
			node.itsNodeType = nodeType
			theSpline.refreshParameterization()
			self.clearCachedRLERuns(from: curve)
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theDoOperation   = { theOperation(newType) }
		let theUndoOperation = { theOperation(oldType) }
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}
	
	func changeUnitCellShape(
		oldShape: UnitCellShape,
		newShape: UnitCellShape
	) {

		//	Adjust itsTranslations to realize the newShape,
		//	while leaving the translation, rotation and scale
		//	of the drawing more-or-less untouched, so the user
		//	may reliably translate, rotate and zoom the drawing
		//	independently of any Undo/Redo operations.

		let theOperation = { shape in
		
			self.setUnitCellShape(shape)

			//	Changing the unit cell shape typically requires Brushstrokes
			//	to be drawn slightly differently in the unit cell texture
			//	(using a different ellipse for the brush), which may
			//	invalidate cached flood fill masks.
			self.clearCachedRLERuns()
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsSingularitiesTextureRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theDoOperation   = { theOperation(newShape) }
		let theUndoOperation = { theOperation(oldShape) }
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}
	
	func changeUnitCellPlacement(
		oldPlacement: UnitCellPlacement,
		newPlacement: UnitCellPlacement
	) {

		//	Note:  This function gets called only in response
		//	to taps on the Realign button.  By contrast,
		//	when the user uses a 2-finger gesture to translate,
		//	rotate or zoom the drawing, the change gets applied
		//	directly, without putting it onto the Undo stack.

		let theOperation = { placement in
		
			self.itsUnitCellPlacement = placement

			//	Changing the unit cell placement typically requires Brushstrokes
			//	to be drawn slightly differently in the unit cell texture
			//	(using a different ellipse for the brush), which may
			//	invalidate cached flood fill masks.
			self.clearCachedRLERuns()
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsSingularitiesTextureRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theDoOperation   = { theOperation(newPlacement) }
		let theUndoOperation = { theOperation(oldPlacement) }
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}
	
	func changeWallpaperGroup(
		to newWallpaperGroup: WallpaperGroup,
		placement newUnitCellPlacement: UnitCellPlacement
	) {

		let theOldWallpaperGroup = itsWallpaperGroup
		let theOldUnitCellPlacement = itsUnitCellPlacement

		let theOperation = { wallpaperGroup, unitCellPlacement in
		
			self.itsWallpaperGroup = wallpaperGroup
			self.itsUnitCellPlacement = unitCellPlacement

			//	Changing itsUnitCellPlacement typically requires Brushstrokes
			//	to be drawn slightly differently in the unit cell texture
			//	(using a different ellipse for the brush), which may
			//	invalidate cached flood fill masks.
			self.clearCachedRLERuns()
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsSingularitiesTextureRedrawRequestCount += 1
			self.itsUndoRedoCount += 1

			UserDefaults.standard.set(
				wallpaperGroup.rawValue,
				forKey: "default symmetry group")
		}
		let theDoOperation   = { theOperation(   newWallpaperGroup,    newUnitCellPlacement) }
		let theUndoOperation = { theOperation(theOldWallpaperGroup, theOldUnitCellPlacement) }
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}
	
	func changeColor(
		of elements: [DrawingElement],
		to newColor: LinearDisplayP3Color
	) {
		guard let theFirstElement = elements.first else {	//	should never fail
			return
		}
		let theOldColor = theFirstElement.itsColor
		
		let theOperation = { color in
		
			for theElement in elements {
				theElement.itsColor = color
			}
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theDoOperation   = { theOperation(   newColor) }
		let theUndoOperation = { theOperation(theOldColor) }
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}

	func changeThickness(
		of brushstrokes: [Brushstroke],	//	listed in the same order they get drawn
		from oldThickness: Double,
		to newThickness: Double
	) {
	
		let theOperation = { thickness in
		
			for theBrushstroke in brushstrokes {
				theBrushstroke.itsThickness = thickness
			}

			//	theFirstBrushstroke is not just the first item in the Array,
			//	it's also the first of those brushstrokes to get drawn at render time.
			if let theFirstBrushstroke = brushstrokes.first {	//	should never fail
			
				//	The Brushstrokes' thickness might affect the extent
				//	of subsequent flood fills, so when we re-render the scene
				//	we'll need to recompute all fills that come after theFirstBrushstroke.
				self.clearCachedRLERuns(from: theFirstBrushstroke)
			}
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theDoOperation   = { theOperation(newThickness) }
		let theUndoOperation = { theOperation(oldThickness) }
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}

	func changeElementArray(
		from oldElementArray: [DrawingElement],
		to newElementArray: [DrawingElement]
	) {

		//	While it would be correct to delete all RLE runs
		//	from both the oldElementArray and the newElementArray,
		//	for better performance we may check whether the two Arrays
		//	share a common initial sequence and, if so, avoid needlessly
		//	deleting and recomputing the RLE runs for that initial sequence.

		let theMinNumElements = min(oldElementArray.count, newElementArray.count)
		let theFirstDifferenceIndex = (0 ..< theMinNumElements).first(where:
			{ i in oldElementArray[i] !== newElementArray[i] }) ?? theMinNumElements

		let theOperation = { (oldArray: [DrawingElement], newArray: [DrawingElement]) in
		
			self.itsElements = newArray
			
			//	Clear unneeded RLE runs on the old Array
			//	to reduce memory demands on the Undo stack.
			for i in theFirstDifferenceIndex ..< oldArray.count {
				if let theFill = oldArray[i] as? Fill {
					theFill.itsCachedRLERunsBuffer = nil
				}
			}
			
			//	Clear unneeded RLE runs on the new Array to let
			//	the Renderer know that it needs to recompute them.
			for i in theFirstDifferenceIndex ..< newArray.count {
				if let theFill = newArray[i] as? Fill {
					theFill.itsCachedRLERunsBuffer = nil
				}
			}

			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theDoOperation   = { theOperation(oldElementArray, newElementArray) }
		let theUndoOperation = { theOperation(newElementArray, oldElementArray) }
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}
	
	func changeNothing() {
	
		//	Do nothing.
		//	Please see the call to this function in KaleidoPaintContentView
		//	for an explanation of why this is useful.

		let theNullOperation = {
			self.itsUndoRedoCount += 1
		}
		
		doSomethingUndoably(
			doOperation: theNullOperation,
			undoOperation: theNullOperation)
	}

	func changeLegacyDrawingBrushstrokeThicknesses(
		from oldThicknessesArray: [Double?],
		to newThicknessesArray: [Double?]
	) {

		//	I'm not keen on passing data in parallel Arrays,
		//	but I was even less keen on writing the code
		//	needed to make a proper copy of itsDrawingElements,
		//	so here we are.  Let's at least make sure
		//	the oldThicknessesArray and the newThicknessesArray
		//	have the correct length.
		//
		let theElementCount = itsElements.count
		if oldThicknessesArray.count != theElementCount
		|| newThicknessesArray.count != theElementCount {
		
			assertionFailure("changeLegacyDrawingBrushstrokeThicknesses() received arrays of incorrect length")
			return
		}

		let theOperation = { (thicknessArray: [Double?]) in
		
			//	Install the new brushstroke thicknesses
			for i in 0 ..< theElementCount {
				let theElement = self.itsElements[i]
				if let theBrushstroke = theElement as? Brushstroke {
					if let theNewThickness = thicknessArray[i] {
						theBrushstroke.itsThickness = theNewThickness
					} else {
						assertionFailure("newThicknessesArray is missing a Brushstroke thickness")
					}
				}
			}

			self.clearCachedRLERuns()
		
			self.changeCount += 1
			self.itsBaseDrawingTextureFullRedrawRequestCount += 1
			self.itsUndoRedoCount += 1
		}
		let theDoOperation   = { theOperation(newThicknessesArray) }
		let theUndoOperation = { theOperation(oldThicknessesArray) }
		
		doSomethingUndoably(
			doOperation: theDoOperation,
			undoOperation: theUndoOperation)
	}

	func doSomethingUndoably(
		doOperation:   @escaping () -> Void,
		undoOperation: @escaping () -> Void
	) {

		guard let theUndoManager = itsUndoManager
		else { return }
	
		doOperation()

		theUndoManager.registerUndo(withTarget: self) { doc in
			
			//	When the user requests an Undo action,
			//	the UndoManager will
			//
			//	1. Swap the undo and redo queues,
			//
			//	2. call this code,
			//
			doc.doSomethingUndoably(
				doOperation: undoOperation,
				undoOperation: doOperation)
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

	func clearCachedRLERuns(
		from startingElement: DrawingElement? = nil
	) {
		guard let theFirstElement = itsElements.first else {
			return	//	itsElements is empty
		}
		let theStartingElement = startingElement ?? theFirstElement
	
		guard let theStartingIndex = itsElements.firstIndex(where: { element in
			element === theStartingElement
		}) else {
			return	//	should never occur
		}
		
		let theAffectedElements = itsElements.dropFirst(theStartingIndex)
	
		for theElement in theAffectedElements {
		
			if let theFill = theElement as? Fill {
			
				theFill.itsCachedRLERunsBuffer = nil
			}
		}
	}

// MARK: -
// MARK: Aspect ratio

	func getUnitCellShape(
	) -> UnitCellShape {

		let theRigidity = itsWallpaperGroup.torusGroup.itsRigidity
		let theTranslations = itsUnitCellPlacement.itsTranslations

		let theAspectRatio: Double
		let theShear: Double
		switch theRigidity {
		
		case .fullyFlexible:
		
			let theComplexRatio = complexQuotient(
										numerator:   theTranslations[1],
										denominator: theTranslations[0])

			theAspectRatio = theComplexRatio[1]
			theShear = theComplexRatio[0]
			
		case .rectangular:
		
			theAspectRatio = length(theTranslations[1])
						   / length(theTranslations[0])
			theShear = 0.0
			
		case .rhombic:

			//	The rhombus has a "main diagonal" whose length is
			
			let theMainDiagonalLength  = length(theTranslations[0] + theTranslations[1])
			
			//	and a "cross diagonal" whose length is
			
			let theCrossDiagonalLength = length(theTranslations[1] - theTranslations[0])
			
			//	The aspect ratio is the ratio of those two lengths
			
			theAspectRatio = (
				theMainDiagonalLength > 0.0 ?	//	should never fail
					theCrossDiagonalLength / theMainDiagonalLength :
					1.0
			)
			theShear = 0.0
			
		case .rigid:	//	should never occur
		
			theAspectRatio = 1.0
			theShear = 0.0
		}
		
		return UnitCellShape(
			aspectRatio: theAspectRatio,
			shear: theShear)
	}
	
	func setUnitCellShape(
		_ unitCellShape: UnitCellShape
	) {

		let theRigidity = itsWallpaperGroup.torusGroup.itsRigidity
		var theTranslations = itsUnitCellPlacement.itsTranslations

		switch theRigidity {
		
		case .fullyFlexible:

			let theComplexRatio = SIMD2<Double>(
									unitCellShape.shear,
									unitCellShape.aspectRatio)
			
			let theOldArea = theTranslations.determinant
			
			theTranslations[1] = complexProduct(
									z: theTranslations[0],
									w: theComplexRatio)
			
			let theNewArea = theTranslations.determinant
			
			if theNewArea > 0.0 {	//	should never fail
			
				let theFactor = sqrt(theOldArea / theNewArea)
				
				theTranslations *= theFactor
			}

		case .rectangular:
		
			let theOldAspectRatio = length(theTranslations[1])
								  / length(theTranslations[0])
			
			let theNewAspectRatio = unitCellShape.aspectRatio
			
			//	In practice this clamping should never be needed,
			//	but let's clamp anyhow just to be safe.
			let theOldClampedAspectRatio =
				min(max(theOldAspectRatio, 0.001), 1000.0)
			
			let theFactor = sqrt(theNewAspectRatio / theOldClampedAspectRatio)
			
			theTranslations[0] /= theFactor
			theTranslations[1] *= theFactor
			
		case .rhombic:

			//	See comments for the .rhombic case in getUnitCellShape() above.
			
			let theMainDiagonal  = theTranslations[0] + theTranslations[1]
			let theCrossDiagonal = theTranslations[1] - theTranslations[0]

			let theMainDiagonalLength  = length(theMainDiagonal)
			let theCrossDiagonalLength = length(theCrossDiagonal)
			
			if theMainDiagonalLength  > 0.0
			&& theCrossDiagonalLength > 0.0 {

				let theDoubleArea = theMainDiagonalLength * theCrossDiagonalLength
				
				let theNewAspectRatio = unitCellShape.aspectRatio
				
				let theNewMainDiagonalLength  = sqrt(theDoubleArea / theNewAspectRatio)
				let theNewCrossDiagonalLength = sqrt(theDoubleArea * theNewAspectRatio)
				
				let theNewMainDiagonal  = theMainDiagonal
										* (theNewMainDiagonalLength  / theMainDiagonalLength )

				let theNewCrossDiagonal = theCrossDiagonal
										* (theNewCrossDiagonalLength / theCrossDiagonalLength)
				
				theTranslations[0] = 0.5 * theNewMainDiagonal
								   - 0.5 * theNewCrossDiagonal

				theTranslations[1] = 0.5 * theNewMainDiagonal
								   + 0.5 * theNewCrossDiagonal
				
			} else {	//	should never occur
				
				theTranslations = matrix_identity_double2x2
			}
			
		case .rigid:
			break	//	should never occur
		}

		itsUnitCellPlacement.itsTranslations = theTranslations
	}


// MARK: -
// MARK: Save tileable rectangle
	
	func prepareModelToExportTileableRectangle(
		availableWidthPx: Int,
		availableHeightPx: Int
	) -> (Int, Int) {	//	(specialWidthPx, specialHeightPx)
	
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
		itsRestorableUnitCellPlacement = itsUnitCellPlacement

		//	Our task now is to change the UnitCellPlacement so that
		//	exactly one copy of the unit cell will appear (for rectangular groups)
		//	or exactly two copies (for rhombic groups).
		
		let theShapeConstraints = itsWallpaperGroup.torusGroup.itsUnitCellShapeConstraints
		let theUnitCellTranslations = itsUnitCellPlacement.itsTranslations
		
		let theRawRectTranslations: simd_double2x2	//	in drawing coordinates
		let theRawSkew: Double
		
		if theShapeConstraints.contains(.angle_2π_over_4) {
	
			//	The group is rectangular.
		
			//	The unit cell may be exported as is.
			theRawRectTranslations = theUnitCellTranslations
			
			//	The unit cell is rectangular, so no skew.
			theRawSkew = 0.0

		} else if theShapeConstraints.contains(.rhombus) {
	
			//	The group is rhombic (but not square).
			//	It may be a triangular or hexagonal group,
			//	or it may be a group with mirror lines
			//	and/or glide reflections.

			//	The tileable rectangle's horizontal translation
			//	will be the sum of the rhomb's translations, while
			//	the tileable rectangle's vertical translation
			//	will be the difference of the rhomb's translations.
			//
			theRawRectTranslations = simd_double2x2(
				theUnitCellTranslations[0] + theUnitCellTranslations[1],
				theUnitCellTranslations[1] - theUnitCellTranslations[0] )
			
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
			let theLength0 = length(theUnitCellTranslations[0])
			if theLength0 == 0.0 {
				assertionFailure("Internal error:  itsTranslations[0] has length zero")
				return (availableWidthPx, availableHeightPx)
			}
			
			//	Split itsTranslations[1] into a component parallel to itsTranslations[0]
			//	and a component perpendicular to itsTranslations[0].
			let theUnitVector0 = theUnitCellTranslations[0] / theLength0
			let theParallelComponentLength = dot(theUnitCellTranslations[1], theUnitVector0)
			let theParallelComponent = theParallelComponentLength * theUnitVector0
			let thePerpendicularComponent = theUnitCellTranslations[1] - theParallelComponent

			//	The exported rectangle's horizontal side matches the base of the parallelogram.
			//	The vertical side is the vertical line shown in the diagram above.
			theRawRectTranslations = simd_double2x2(
				theUnitCellTranslations[0],
				thePerpendicularComponent)

			//	Note how skewed the unit cell is.
			theRawSkew = theParallelComponentLength
		}

		let theRawRectWidth  = length(theRawRectTranslations[0])
		let theRawRectHeight = length(theRawRectTranslations[1])
		
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
		if theRawRectWidth  * Double(availableHeightPx)
		 > theRawRectHeight * Double(availableWidthPx) {
		
			//	The width is more crowded.
			theRectWidthPx = availableWidthPx
			theRectHeightPx = Int(round( (theRawRectHeight / theRawRectWidth) * Double(theRectWidthPx) ))
			
			//	Just to be safe, clamp theRectHeightPx to the range [1, availableHeightPx].
			theRectHeightPx = max(1, min(availableHeightPx, theRectHeightPx))
			
		} else {
		
			//	The height is more crowded.
			theRectHeightPx = availableHeightPx
			theRectWidthPx = Int(round( (theRawRectWidth / theRawRectHeight) * Double(theRectHeightPx) ))
			
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
		let theSkewPx = round( Double(theRectWidthPx) * (theRawSkew / theRawRectWidth) )

		//	As explained in the extended comment on "Coordinate systems"
		//	in KaleidoPaintCoordinateSystems.swift, the image's diagonal
		//	has length exactly 1.0 in drawing coordinates, by definition.
		let theDrawingUnitsPerPixel = 1.0 / sqrt(Double( theRectWidthPx  * theRectWidthPx
													   + theRectHeightPx * theRectHeightPx ))
		
		//	Scale the translations (defined in the comment above) and theSkewPx
		//	so that the rectangle exactly fills the image.
		let theScaledWidth  = theDrawingUnitsPerPixel * Double(theRectWidthPx)
		let theScaledHeight = theDrawingUnitsPerPixel * Double(theRectHeightPx)
		let theScaledSkew   = theDrawingUnitsPerPixel * theSkewPx

		//	Set itsUnitCellPlacement's translations to fit theRectTranslations and theSkew.
		if theShapeConstraints.contains(.angle_2π_over_4) {
	
			//	The group is rectangular.
			
			itsUnitCellPlacement.itsTranslations = simd_double2x2(
				SIMD2<Double>(theScaledWidth, 0.0),
				SIMD2<Double>(0.0, theScaledHeight)
			)

		} else if theShapeConstraints.contains(.rhombus) {
	
			//	The group is rhombic (but not square).
			//	It may be a triangular or hexagonal group,
			//	or it may be a group with mirror lines
			//	and/or glide reflections.

			itsUnitCellPlacement.itsTranslations = simd_double2x2(
				SIMD2<Double>(
					 0.5 * theScaledWidth,
					-0.5 * theScaledHeight),
				SIMD2<Double>(
					 0.5 * theScaledWidth,
					+0.5 * theScaledHeight)
			)
	
		} else {

			//	The group is either ○ or 2222.
			//	The unit cell may be any parallelogram.

			itsUnitCellPlacement.itsTranslations = simd_double2x2(
				SIMD2<Double>(theScaledWidth, 0.0),
				SIMD2<Double>(theScaledSkew, theScaledHeight)
			)
		}

		//	We can place itsUnitCellPlacement's corner wherever it looks good,
		//	for example at the image's lower-left corner.
		itsUnitCellPlacement.itsCorner = SIMD2<Double>(
											-0.5 * theScaledWidth,
											-0.5 * theScaledHeight)

		//	Note:  We've changed the unit cell's placement but not its shape,
		//	so there's no need to redraw the unit cell textures.

		//	Let the caller know how big to make the image.
		return (theRectWidthPx, theRectHeightPx)
	}
	
	func restoreModelAfterExportingTileableRectangle() {
	
		//	Undo the action of prepareModelToExportTileableRectangle().
		
		guard let theRestorableUnitCellPlacement = itsRestorableUnitCellPlacement else {
			assertionFailure("Internal error:  itsRestorableUnitCellPlacement is unexpectedly nil")
			return
		}
		
		itsUnitCellPlacement = theRestorableUnitCellPlacement
		itsRestorableUnitCellPlacement = nil

		//	Note:  We've changed the unit cell's placement but not its shape,
		//	so there's no need to redraw the unit cell textures.
	}


// MARK: -
// MARK: Touch handling - tap
	
	func singleTapForDrawing(
		at tapPoint: DisplayPoint
	) {

		//	Ignore single taps while content is locked.
		if itsContentIsLocked {
			return
		}

		precondition(
			tapPoint.viewWidth > 0.0 && tapPoint.viewHeight > 0.0,
			"doubleTapForDrawing() received tap in view of zero width or zero height")
		
		let theSingleTapPointInStrictUnitCellCoordinates
			= convertDisplayCoordinatesToStrictUnitCellCoordinates(
				tapPoint,
				unitCellPlacement: itsUnitCellPlacement)

		let theNewDot = Dot(
			color: itsBrushColor,
			center: theSingleTapPointInStrictUnitCellCoordinates,
			thickness: itsBrushThickness)

		appendDrawingElement(theNewDot)
	}

	func doubleTapForDrawing(
		at tapPoint: DisplayPoint
	) {
	
		//	Ignore double taps while content is locked.
		if itsContentIsLocked {
			return
		}

		precondition(
			tapPoint.viewWidth > 0.0 && tapPoint.viewHeight > 0.0,
			"doubleTapForDrawing() received tap in view of zero width or zero height")
		
		let theDoubleTapPointInStrictUnitCellCoordinates
			= convertDisplayCoordinatesToStrictUnitCellCoordinates(
				tapPoint,
				unitCellPlacement: itsUnitCellPlacement)

		let theNewFill = Fill(
			color: itsFillColor,
			fillPoint: theDoubleTapPointInStrictUnitCellCoordinates)

		appendDrawingElement(theNewFill)
	}

	func singleTapForEditing(
		at tapPoint: DisplayPoint,
		editorIsShown: Binding<Bool>,
		editorAnchor: Binding<PopoverAttachmentAnchor>
	) {
		//	We should never be in Edit mode while the drawing is locked,
		//	but check anyhow, just to be safe.
		if itsContentIsLocked {
			return
		}

		precondition(
			tapPoint.viewWidth > 0.0 && tapPoint.viewHeight > 0.0,
			"singleTapForEditing() received tap in view of zero width or zero height")
		
		let theTapPointInExtendedUnitCellCoordinates
			= convertDisplayCoordinatesToExtendedUnitCellCoordinates(
				tapPoint,
				unitCellPlacement: itsUnitCellPlacement)
		
		itsControlHandleHit
			= possibleControlHandleHit(theTapPointInExtendedUnitCellCoordinates)
		
		//	Did the tap hit a control handle?
		if let theHitControlHandle = itsControlHandleHit {
		   			
			let theHandleCenter
				= convertExtendedUnitCellCoordinatesToDisplayCoordinates(
					theHitControlHandle.itsHitCenter,
					unitCellPlacement: itsUnitCellPlacement,
					viewWidth: tapPoint.viewWidth,
					viewHeight: tapPoint.viewHeight)
			
			//	Anchoring the Editor at the control handle's center looks good.
			//	In principle the Editor could instead be anchored to a square
			//	containing the control handle (as in the legacy version of KaleidoPaint)
			//	but doing so would be messy (requiring an Anchor<CGRect>.Source
			//	and GeometryReader, it seems) and there's no obvious advantage.
			//	So let's anchor the popover to the control handle's center
			//	and keep things simple.
			
			editorIsShown.wrappedValue = true
			editorAnchor.wrappedValue = .point(UnitPoint(
				x: theHandleCenter.x / theHandleCenter.viewWidth,
				y: 1.0 - (theHandleCenter.y / theHandleCenter.viewHeight)))

		} else {

			editorIsShown.wrappedValue = false
			editorAnchor.wrappedValue = .point(UnitPoint(x: 0.5, y: 0.5))	//	just to be tidy
		}
		
		itsBaseDrawingTextureFullRedrawRequestCount += 1
		changeCount += 1
	}
	
	func possibleControlHandleHit(
		_ touchPointInExtendedUnitCellCoordinates: SIMD2<Double>
	) -> ControlHandleHit? {
	
		//	Test each DrawingElement for a control-handle hit.
		//	If several control handles sit close to each other,
		//	select the one closest to the tap point.

		let theFillMarkerRadius = fillMarkerRadius()	//	used only for Fills

		var thePossibleHitControlHandle: ControlHandleHit?
		var theTapError = Double.infinity

		for theElement in itsElements {
		
			if let theHitControlHandle = theElement.hitControlHandle(
				touchPointInExtendedUnitCellCoordinates: touchPointInExtendedUnitCellCoordinates,
				wallpaperGroup: itsWallpaperGroup,
				metricOfDet1: itsUnitCellPlacement.itsMetricOfDet1,
				fillMarkerRadius: theFillMarkerRadius) {
				
				if theHitControlHandle.itsTapError < theTapError {
				
					thePossibleHitControlHandle = theHitControlHandle
					theTapError = theHitControlHandle.itsTapError
				}
			}
		}
		
		return thePossibleHitControlHandle
	}
	

// MARK: -
// MARK: Touch handling - single touch

	func touchBegan(
		at initialTouchPoint: DisplayPoint
	) {

		//	Ignore all 1-finger motions while content is locked.
		if itsContentIsLocked {
			return
		}

		let theExtendedUnitCellPoint
			= convertDisplayCoordinatesToExtendedUnitCellCoordinates(
				initialTouchPoint,
				unitCellPlacement: itsUnitCellPlacement)
		
		switch itsTouchMode {
		
		case .draw:
			touchBeganForDrawing(at: theExtendedUnitCellPoint)
			
		case .edit:
			touchBeganForEditing(at: theExtendedUnitCellPoint)
		}
	}

	func touchMoved(
		to touchPoint: DisplayPoint
	) {

		//	Note:  Because theDrawingView sets isExclusiveTouch = true,
		//	the user can't possibly lock or unlock the drawing
		//	while a touch is in progress.  The itsContentIsLocked
		//	will be true here iff it was true in touchBegan().
		//
		if itsContentIsLocked {
			return
		}

		let theExtendedUnitCellPoint
			= convertDisplayCoordinatesToExtendedUnitCellCoordinates(
				touchPoint,
				unitCellPlacement: itsUnitCellPlacement)
		
		if itsCurveInProgress != nil {
			touchMovedForDrawing(at: theExtendedUnitCellPoint)
		} else {
			touchMovedForEditing(at: theExtendedUnitCellPoint)
		}
	}

	func touchEnded() {

		//	Note:  Because theDrawingView sets isExclusiveTouch = true,
		//	the user can't possibly lock or unlock the drawing
		//	while a touch is in progress.  The itsContentIsLocked
		//	will be true here iff it was true in touchBegan().
		//
		if itsContentIsLocked {
			return
		}

		if itsCurveInProgress != nil {
			touchEndedForDrawing()
		} else {
			touchEndedForEditing()
		}
	}

	func touchCancelled() {

		//	Note:  Because theDrawingView sets isExclusiveTouch = true,
		//	the user can't possibly lock or unlock the drawing
		//	while a touch is in progress.  The itsContentIsLocked
		//	will be true here iff it was true in touchBegan().
		//
		if itsContentIsLocked {
			return
		}

		if itsCurveInProgress != nil {
			touchCancelledForDrawing()
		} else {
			touchCancelledForEditing()
		}
	}
	

// MARK: -
// MARK: Touch handling - single touch - drawing

	private func touchBeganForDrawing(
		at extendedUnitCellPoint: SIMD2<Double>
	) {
	
		assert(
			itsCurveInProgress == nil,
			"unexpected curve-in-progress")

		//	Choose itsCurveInProgressTouchOffset so that
		//	theOffsetPoint will sit in the unit cell [0,1]×[0,1].
		
		let theStrictUnitCellPoint
			= convertExtendedUnitCellCoordinatesToStrictUnitCellCoordinates(extendedUnitCellPoint)

		//	In principle theCurveInProgressTouchOffset is an integer,
		//	but of course in practice it might come out as, say,
		//	17.9999999 or 18.0000001.
		let theCurveInProgressTouchOffset = theStrictUnitCellPoint - extendedUnitCellPoint
		
		itsCurveInProgressTouchOffset
			= SIMD2<Int>(
				Int(round(theCurveInProgressTouchOffset[0])),
				Int(round(theCurveInProgressTouchOffset[1])))

		//	Initialize the potential basepoints (x,y) with x ∈ {-1,0,+1} and y ∈ {-1,0,+1}.
		initializePotentialBasepoints(curveStartInStrictUnitCellCoordinates: theStrictUnitCellPoint)
	
		//	Create an empty curve...
		let theCurveInProgress = Curve(
			color: itsBrushColor,
			thickness: itsBrushThickness)

		//	... and then add the starting node.
		let theStartingNode = SplineNode(location: theStrictUnitCellPoint, type: .corner)
		theCurveInProgress.itsSpline.append(theStartingNode)
		theCurveInProgress.itsSpline.refreshParameterization()
		
		itsCurveInProgress = theCurveInProgress
		itsCurveInProgressTextureRedrawRequestCount += 1
		changeCount += 1
	}
	
	private func touchMovedForDrawing(
		at extendedUnitCellPoint: SIMD2<Double>
	) {
	
		guard let theCurveInProgress = itsCurveInProgress else {
			return
		}
		
		let theOffsetPoint = extendedUnitCellPoint + SIMD2<Double>(itsCurveInProgressTouchOffset)

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
		guard let thePreviousNode = theCurveInProgress.itsSpline.itsNodes.last else {
			assertionFailure("touchMovedForDrawing() called with empty curve-in-progress")
			return
		}
		if theOffsetPoint == thePreviousNode.itsNodeLocation {	//	check for exact equality
			return
		}
		
		if updatePotentialBasepoints(newPoint: theOffsetPoint) {

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

			let theNewNode = SplineNode(location: theOffsetPoint, type: .corner)
			theCurveInProgress.itsSpline.append(theNewNode)
			theCurveInProgress.itsSpline.refreshParameterization()

			itsCurveInProgressTextureRedrawRequestCount += 1
			changeCount += 1
		}
	}
	
	private func touchEndedForDrawing() {
	
		guard let theCurveInProgress = itsCurveInProgress else {
			return
		}

		//	Select one of the valid basepoints.
		guard let theBasepoint = itsCurveInProgressValidBasepoints.first else {	//	should never occur
			return
		}

		//	We want to clear the curve-in-progress
		//	whether or not we encounter an error.
		itsCurveInProgress = nil
		itsCurveInProgressValidBasepoints = []
		itsCurveInProgressAcceptsNewPoints = false
		itsCurveInProgressTextureRedrawRequestCount += 1	//	to clear the texture
		changeCount += 1

		//	Renormalize itsCurveInProgress relative to theBasepoint,
		//	so that the whole curve stays within the padded safe region.
		for theNode in theCurveInProgress.itsSpline.itsNodes {
		
			theNode.itsNodeLocation -= SIMD2<Double>(theBasepoint)
		}

		let theNumNodes = theCurveInProgress.itsSpline.itsNodes.count

		//	The user interface should never call touchBegan()
		//	without also calling touchMoved(), so a curve should
		//	always have at least two nodes.
		if theNumNodes < 2 {
			return
		}

		//	The first and last nodes count as special cases of corners,
		//	and get treated the same way (the spline's second derivatives get
		//	set to zero at all corners, including first and last nodes).
		theCurveInProgress.itsSpline.itsNodes[       0       ].itsNodeType = .corner
		theCurveInProgress.itsSpline.itsNodes[theNumNodes - 1].itsNodeType = .corner

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
		for i in 1 ..< (theNumNodes - 1) {
			theCurveInProgress.itsSpline.itsNodes[i].itsNodeType = .smooth
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
	
	private func ramerDouglasPeucker(
		_ curve: Curve
	) {
	
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
		let theSpline = curve.itsSpline
		
		if theSpline.itsNodes.count < 3 {
			return
		}
		
		//	The Ramer-Douglas-Peucker algorithm operates recursively.
		//	Given a series of points, it always returns the first and last nodes,
		//	along with any interior nodes that it wants to preserve.
		//
		let theRamerDouglasPeuckerOutput: [SplineNode]
		
			= [theSpline.itsNodes[0]]								//	first node

			+ ramerDouglasPeuckerInteriorNodes(						//	interior nodes (if any)
				between: 0,
				and: theSpline.itsNodes.count - 1,
				inSpline: theSpline,
				tolerance: itsSmoothingTolerance)

			+ [theSpline.itsNodes[theSpline.itsNodes.count - 1]]	//	last node

		theSpline.itsNodes = theRamerDouglasPeuckerOutput
	}
	
	private func ramerDouglasPeuckerInteriorNodes(
		between startIndex: Int,
		and endIndex: Int,
		inSpline spline: CubicSpline,	//	CubicSpline is a class, so passed by reference
		tolerance: Double
	) -> [SplineNode] {

		//	Handle the trivial case that the curve
		//	has no interior nodes at all, to keep
		//	the rest of the code simple.
		if endIndex - startIndex < 2 {
			return []
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
		let theUnitCellSize = sqrt(fabs(
			itsUnitCellPlacement.itsTranslations.determinant))
		let theMetric = theUnitCellSize * itsUnitCellPlacement.itsMetricOfDet1
		
		let p₀ = spline.itsNodes[startIndex].itsNodeLocation
		let p₁ = spline.itsNodes[ endIndex ].itsNodeLocation

		//	Compute the vector connecting the first point to the last point.
		let theParallelVector = p₁ - p₀
		let theTotalLength = sqrt(
			theParallelVector[0] * theMetric[0][0] * theParallelVector[0]
		  + theParallelVector[0] * theMetric[0][1] * theParallelVector[1]
		  + theParallelVector[1] * theMetric[1][0] * theParallelVector[0]
		  + theParallelVector[1] * theMetric[1][1] * theParallelVector[1] )

		//	We want to find the interior point furthest
		//	from the line through the endpoints.
		var theFurthestNodeIndex = 0	//	to get overwritten in code below
		var theFurthestDistance = -1.0	//	to get overwritten in code below

		//	If the curve is a closed loop, then there is no
		//	"approximating line segment" and the standard
		//	Ramer-Douglas-Peucker algorithm requires an easy modification.
		//	Even if the curve if only approximately a closed loop,
		//	it seems more effective to treat it as one.
		//
		if theTotalLength < tolerance {	//	endpoints are closer than the tolerance
		
			//	Find the node that's furthest from the midpoint
			//	of the two nearly-coincident end nodes.

			let theLoopBasepoint = 0.5 * (p₀ + p₁)

			for i in (startIndex + 1) ... (endIndex - 1) {
			
				let p = spline.itsNodes[i].itsNodeLocation
				
				let v = p - theLoopBasepoint

				let theDistance = sqrt(
					v[0] * theMetric[0][0] * v[0]
				  + v[0] * theMetric[0][1] * v[1]
				  + v[1] * theMetric[1][0] * v[0]
				  + v[1] * theMetric[1][1] * v[1] )

				if theDistance > theFurthestDistance {
				
					theFurthestNodeIndex = i
					theFurthestDistance	= theDistance
				}
			}

		} else {	//	endpoints are sufficiently distant (typical case)

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
			var thePerpendicularVector = SIMD2<Double>(
			  -(theMetric[1][0] * theParallelVector[0]  +  theMetric[1][1] * theParallelVector[1]),
				theMetric[0][0] * theParallelVector[0]  +  theMetric[0][1] * theParallelVector[1]
			)

			//	The normal vector is already "normal" in the sense
			//	of being orthogonal to the curve, but we want it
			//	to also be "normal" in the sense of having unit length
			//	relative to the metric,
			//
			//		( n₀ n₁ )( M₀₀ M₀₁ )( n₀ ) = 1
			//		         ( M₁₀ M₁₁ )( n₁ )
			//
			let theLength = sqrt(
				thePerpendicularVector[0] * theMetric[0][0] * thePerpendicularVector[0]
			  + thePerpendicularVector[0] * theMetric[0][1] * thePerpendicularVector[1]
			  + thePerpendicularVector[1] * theMetric[1][0] * thePerpendicularVector[0]
			  + thePerpendicularVector[1] * theMetric[1][1] * thePerpendicularVector[1] )
			//	It's easy to prove that theLength > 0, but check anyhow before dividing by it.
			precondition(
				theLength > 0.0,
				"thePerpendicularVector has zero length")
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
			let theDistanceEvaluator = SIMD2<Double>(
			
				  thePerpendicularVector[0] * theMetric[0][0]
				+ thePerpendicularVector[1] * theMetric[1][0],
				
				  thePerpendicularVector[0] * theMetric[0][1]
				+ thePerpendicularVector[1] * theMetric[1][1]
			)
			
			//	Apply theDistanceEvaluator to either one of the curve's endpoints.
			let theBaseValue = theDistanceEvaluator[0] * p₀[0]
							 + theDistanceEvaluator[1] * p₀[1]

			//	Find the intermediate point that's furthest from
			//	the line that passes through the curve's endpoints.
			for i in (startIndex + 1) ... (endIndex - 1) {

				let p = spline.itsNodes[i].itsNodeLocation

				//	Apply theDistanceEvaluator to theNode.
				let theValue = theDistanceEvaluator[0] * p[0]
							 + theDistanceEvaluator[1] * p[1]

				//	The distance from the line to theNode
				//	is the difference of the two inner products.
				let theDistance = fabs(theValue - theBaseValue)

				//	Is this the further point we've found so far?
				if (theDistance > theFurthestDistance) {
				
					theFurthestNodeIndex = i
					theFurthestDistance	= theDistance
				}
			}
		}
		
		let theInteriorNodes: [SplineNode]
		let theAdHocLengthFactor = 64.0
		if
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
		{
			//	Split the curve at the furthest point and
			//	call ramerDouglasPeuckerInteriorNodes() on the two pieces.

			theInteriorNodes =
			
			  ramerDouglasPeuckerInteriorNodes(			//	interior nodes in first half (if any)
				between: startIndex,
				and: theFurthestNodeIndex,
				inSpline: spline,
				tolerance: tolerance)

			+ [spline.itsNodes[theFurthestNodeIndex]]	//	furthest node

			+ ramerDouglasPeuckerInteriorNodes(			//	interior nodes in second half (if any)
				between: theFurthestNodeIndex,
				and: endIndex,
				inSpline: spline,
				tolerance: tolerance)

		} else {	//	theFurthestDistance ≤ aTolerance
		
			//	All interior points lie within aTolerance
			//	of the segment connecting the curve's endpoints,
			//	so we may ignore them.
			
			theInteriorNodes = []
		}
		
		return theInteriorNodes
	}
	
	private func touchCancelledForDrawing() {
	
		itsCurveInProgress = nil
		itsCurveInProgressValidBasepoints = []
		itsCurveInProgressAcceptsNewPoints = false
		itsCurveInProgressTextureRedrawRequestCount += 1	//	to clear the texture
		changeCount += 1
	}
	

// MARK: -
// MARK: Touch handling - single touch - editing

	
	private func touchBeganForEditing(
		at touchPointInExtendedUnitCellCoordinates: SIMD2<Double>
	) {
	
		itsCurveInProgress = nil	//	unnecessary but safe, and makes our intentions clear

		//	If the touchPointInExtendedUnitCellCoordinates hits a control point
		//	(within some tolerance) remember it.
		//
		itsControlHandleHit = possibleControlHandleHit(
								touchPointInExtendedUnitCellCoordinates)
	}
	
	private func touchMovedForEditing(
		at extendedUnitCellPoint: SIMD2<Double>
	) {
	
		//	For now just move the selected point directly.
		//	We'll put the change onto the Undo stack later,
		//	in response to touchEndedForEditing().
		
		if let theControlHandleHit = itsControlHandleHit {

			let theTransformedPoint3
				= theControlHandleHit.itsSymmetry
				* SIMD3<Double>(extendedUnitCellPoint, 1.0)	//	right-to-left matrix action
			let theTransformedPoint = SIMD2<Double>(
										theTransformedPoint3[0],
										theTransformedPoint3[1])

			//	For Dots and Fills we'll want to normalize theTransformedPoint
			//	to strict unit cell coordinates, so that the user may drag
			//	theDot or theFill as far as desired on the display
			//	without it leaving the area that gets mapped onto the unit cell.
			//
			let theNormalizedPoint = theTransformedPoint - floor(theTransformedPoint)

			if let theDot = theControlHandleHit.itsElement as? Dot {
			
				theDot.itsCenter = theNormalizedPoint
			}
		
			if let theCurve = theControlHandleHit.itsElement as? Curve {
			
				if let theNode = theControlHandleHit.itsNode {
				
					//	Use theTransformedPoint (not theNormalizedPoint)
					//	to maintain continuity with the other nodes in the spline.
					//
					theNode.itsNodeLocation = theTransformedPoint
					
					theCurve.itsSpline.refreshParameterization()
				}
			}
		
			if let theFill = theControlHandleHit.itsElement as? Fill {
			
				theFill.itsFillPoint = theNormalizedPoint
			}
			
			itsBaseDrawingTextureFullRedrawRequestCount += 1
			changeCount += 1
		}
	}
	
	private func touchEndedForEditing() {
		
		if let theControlHandleHit = itsControlHandleHit {

			if let theDot = theControlHandleHit.itsElement as? Dot {
			
				moveDot(
					theDot,
					from: theControlHandleHit.itsHomeCenter,
					to: theDot.itsCenter)
			}
		
			if let theCurve = theControlHandleHit.itsElement as? Curve {
			
				if let theNode = theControlHandleHit.itsNode {
				
					moveSplineNode(
						curve: theCurve,
						node: theNode,
						from: theControlHandleHit.itsHomeCenter,
						to: theNode.itsNodeLocation)
				}
			}
		
			if let theFill = theControlHandleHit.itsElement as? Fill {
			
				moveFill(
					theFill,
					from: theControlHandleHit.itsHomeCenter,
					to: theFill.itsFillPoint)
			}
			
			itsControlHandleHit = nil
		}
	}
	
	private func touchCancelledForEditing() {
	
		//	Move the control point back to where it was when the touch began.
		
		if let theControlHandleHit = itsControlHandleHit {

			if let theDot = theControlHandleHit.itsElement as? Dot {
			
				theDot.itsCenter = theControlHandleHit.itsHomeCenter
			}
		
			if let theCurve = theControlHandleHit.itsElement as? Curve {
			
				if let theNode = theControlHandleHit.itsNode {
				
					theNode.itsNodeLocation = theControlHandleHit.itsHomeCenter

					theCurve.itsSpline.refreshParameterization()
				}
			}
		
			if let theFill = theControlHandleHit.itsElement as? Fill {
			
				theFill.itsFillPoint = theControlHandleHit.itsHomeCenter
			}
			
			itsBaseDrawingTextureFullRedrawRequestCount += 1
			changeCount += 1
			
			itsControlHandleHit = nil
		}
	}


// MARK: -
// MARK: Touch handling - single touch basepoints

	private func initializePotentialBasepoints(
		curveStartInStrictUnitCellCoordinates: SIMD2<Double>
	) {
	
		itsCurveInProgressValidBasepoints = []

		//	Which choices of basepoint (x,y) with x ∈ {-1,0,+1} and y ∈ {-1,0,+1}
		//	would keep anOffsetPoint in the padded safe region
		//	(see explanation in KaleidoPaintWallpaperGroup.swift) ?
		for x in -1 ... +1 {
			for y in -1 ... +1 {
			
				let thePotentialBasepoint = SIMD2<Int>(x, y)
				
				if pointSitsInPaddedSafeRegion(
					extendedUnitCellPoint: curveStartInStrictUnitCellCoordinates,
					potentialBasepoint: thePotentialBasepoint) {
					
					itsCurveInProgressValidBasepoints.insert(thePotentialBasepoint)
				}
			}
		}
		
		//	The default basepoint is guaranteed to be valid,
		//	so accept new points.
		itsCurveInProgressAcceptsNewPoints = true

	}

	private func updatePotentialBasepoints(
		newPoint: SIMD2<Double>
	) -> Bool {

		//	If some previous point got rejected, then
		//	reject all remaining points in the same curve.
		if !itsCurveInProgressAcceptsNewPoints {
			return false
		}

		//	Which nearby choices of basepoint would keep anOffsetPoint
		//	in the padded safe region (see explanation
		//	in KaleidoPaintWallpaperGroup.swift) ?
		let theStillValidBasepoints = itsCurveInProgressValidBasepoints.filter(
		{ potentialBasepoint in
			pointSitsInPaddedSafeRegion(
				extendedUnitCellPoint: newPoint,
				potentialBasepoint: potentialBasepoint)
		})
		
		//	Do any valid basepoints remain?
		if !theStillValidBasepoints.isEmpty {

			//	At least one valid basepoint remains, so we may
			//		accept the newPoint,
			//		replace the old set of basepoints
			//			with the new -- possibly smaller -- subset, and
			//		keep accepting new points on the curve.
			
			itsCurveInProgressValidBasepoints = theStillValidBasepoints
			itsCurveInProgressAcceptsNewPoints = true

			return true	//	accept the newPoint

		} else {
		
			//	No valid basepoints remain, so we must
			//		reject the newPoint,
			//		keep the old set of basepoints, and
			//		stop accepting new points on the curve.
			
			itsCurveInProgressAcceptsNewPoints = false
			
			return false	//	reject the newPoint
		}
	}
	
	private func pointSitsInPaddedSafeRegion(
		extendedUnitCellPoint: SIMD2<Double>,
		potentialBasepoint: SIMD2<Int>
	) -> Bool {
	
		//	Does anExtendedUnitCellPoint sit in the "padded safe region"
		//	(as defined in KaleidoPaintWallpaperGroup.swift) relative
		//	to the given choice of basepoint?
	
		let x = extendedUnitCellPoint[0] - Double(potentialBasepoint[0])
		let y = extendedUnitCellPoint[1] - Double(potentialBasepoint[1])
		
		//	Left boundary of padded safe region
		if x < -1.0 + gSafeRegionInset {
			return false
		}
		
		//	Right boundary of padded safe region
		if x >  2.0 - gSafeRegionInset {
			return false
		}

		//	Bottom boundary of padded safe region
		if y < -1.0 + gSafeRegionInset {
			return false
		}

		//	Top boundary of padded safe region
		if y >  2.0 - gSafeRegionInset {
			return false
		}
		
		//	Bottom-left boundary of padded safe region
		if x + y < -1.0 + gSafeRegionInset {
			return false
		}

		//	Top-right boundary of padded safe region
		if x + y >  3.0 - gSafeRegionInset {
			return false
		}
		
		//	(x,y) sits within the padded safe region.
		return true
	}
	
	
// MARK: -
// MARK: Complex arithmetic

	typealias ComplexNumber = SIMD2<Double>
	
	func complexProduct(
		z: ComplexNumber,
		w: ComplexNumber
	) -> ComplexNumber {
	
		//	(a + bi)(c + di) = (ac - bd) + (ad + bc)i
		
		let a = z[0]
		let b = z[1]
		let c = w[0]
		let d = w[1]
		
		let theProduct = ComplexNumber(a*c - b*d, a*d + b*c)
		
		return theProduct
	}

	func complexQuotient(
		numerator: ComplexNumber,
		denominator: ComplexNumber
	) -> ComplexNumber {
	
		//	a + bi   (a + bi)(c - di)   (ac + bd) + (bc - ad)i
		//	------ = ---------------- = ----------------------
		//	c + di   (c + di)(c - di)          c² + d²
		
		let a = numerator[0]
		let b = numerator[1]
		let c = denominator[0]
		let d = denominator[1]
		
		let theSquaredMagnitude = c*c + d*d
		
		let theQuotient: ComplexNumber
		if theSquaredMagnitude > 0.0 {
		
			theQuotient = ComplexNumber(a*c + b*d, b*c - a*d)
							/ theSquaredMagnitude
		
		} else {	//	theSquaredMagnitude == 0.0
		
			assertionFailure("complex division by zero")
			theQuotient = ComplexNumber(0.0, 1.0)
		}
		
		return theQuotient
	}


// MARK: -
// MARK: Dynamically sized fill marker

	func fillMarkerRadius() -> Double {	//	mean radius in unit cell coordinates
	
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

		let theNominalMarkerRadius = 0.0078125	//	mean radius in unit cell coordinates
		let theUnitCellArea = itsUnitCellPlacement.itsTranslations.determinant
		let theScaledMarkerRadius = (
			theUnitCellArea > 0.0 ?	//	should never fail
				theNominalMarkerRadius / sqrt(theUnitCellArea) :
				theNominalMarkerRadius
		)
		let theCappedMarkerRadius = min(0.0078125, theScaledMarkerRadius)

		return theCappedMarkerRadius	//	mean radius in unit cell coordinates
	}
}


//	For use when converting from KaleidoPaint File Format 1.1 to 1.2.
func convertColorFromHSLtoHSB(
	_ oldBaseR: Double,	//	the old "base color"
	_ oldBaseG: Double,
	_ oldBaseB: Double,
	//	assume a == 1  (that is, opacity α == 1)
	_ lightness: Double
) -> (Double, Double, Double, Double) {	//	(newBaseR, newBaseG, newBaseB, brightness)

	//	The first time the current version of KaleidoPaint reads
	//	a drawing file in the legacy version 1.1 of the file format,
	//	it will need to convert the legacy "base color + lightness"
	//	to the slightly newer "base color + brightness".
	//	(The base color also changes, of course.)
		
	var theNewBaseR: Double
	var theNewBaseG: Double
	var theNewBaseB: Double
	let theNewBrightness: Double
	
	if lightness <= 0.5 {
	
		//	The old base color (at lightness = 1/2) and
		//	the new base color (at brightness 1) lie on the same ray
		//	from the origin, so computing the latter from the former is easy.
		var theMaxComponentValue = max(oldBaseR, oldBaseG, oldBaseB)

		//	If numerical errors left us with, say, 0.9999999 instead of 1.0000000,
		//	snap to 1.0 exactly.
		if theMaxComponentValue > 0.99999 {
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
		if theMaxComponentValue < 0.5 {
			theMaxComponentValue = 0.5
		}

		//	Rescale the base color to have maximum component value 1.0.
		let theFactor = 1.0 / theMaxComponentValue
		theNewBaseR = oldBaseR * theFactor
		theNewBaseG = oldBaseG * theFactor
		theNewBaseB = oldBaseB * theFactor
		
		//	The old lightness determines the new brightness.
		theNewBrightness = 2.0 * lightness * theMaxComponentValue
	}
	else
	{
		//	The old base color (at lightness = 1/2) and
		//	the new base color (at brightness 1) lie on different rays
		//	from the origin, so to compute the latter we must first
		//	explicitly calculate the RGB color itself.

		//	Average the base color with pure white (1,1,1)
		//	to recover the RGB color itself.
		let theColorFactor = (1.0 - lightness) / 0.5
		let theWhiteFactor = 1.0 - theColorFactor
		var theColorR = theColorFactor * oldBaseR
					  + theWhiteFactor * 1.0
		var theColorG = theColorFactor * oldBaseG
					  + theWhiteFactor * 1.0
		var theColorB = theColorFactor * oldBaseB
					  + theWhiteFactor * 1.0

		//	If numerical errors left us with, say, 0.9999999 instead of 1.0000000,
		//	snap to 1.0 exactly.  (This may leave other numerical errors,
		//	for example 0.4999999, uncorrected, but trying to fix them would be messy.)
		if theColorR > 0.99999 {
			theColorR = 1.0
		}
		if theColorG > 0.99999 {
			theColorG = 1.0
		}
		if theColorB > 0.99999 {
			theColorB = 1.0
		}
		
		//	Note the color's brightness, which by definition is max(R,G,B).
		theNewBrightness = max(theColorR, theColorG, theColorB)

		//	Project the color onto the cube's surface of brightness 1
		//	to get the new base color.
		//	(itsBrightness is at least 1/2, so there's no risk of division by zero.)
		let theFactor = 1.0 / theNewBrightness
		theNewBaseR = theColorR * theFactor
		theNewBaseG = theColorG * theFactor
		theNewBaseB = theColorB * theFactor
	}
		
	//	If numerical errors left us with, say, 0.9999999 instead of 1.0000000,
	//	snap to 1.0 exactly.  (This may leave other numerical errors,
	//	for example 0.4999999, uncorrected, but trying to fix them would be messy.)
	if theNewBaseR > 0.99999 {
		theNewBaseR = 1.0
	}
	if theNewBaseG > 0.99999 {
		theNewBaseG = 1.0
	}
	if theNewBaseB > 0.99999 {
		theNewBaseB = 1.0
	}
	
	return (theNewBaseR, theNewBaseG, theNewBaseB, theNewBrightness)
}

//	For use when converting from KaleidoPaint File Format 1.2 to 1.3.
func convertColorFromGammaEncodedToLinear(
	_ oldBaseR: Double,	//	the old "base color"
	_ oldBaseG: Double,
	_ oldBaseB: Double,
	//	assume a == 1  (that is, opacity α == 1)
	_ oldBrightness: Double
) -> (Double, Double, Double, Double) {	//	returns new (R, G, B, brightness)

	//	This function is used only when converting from File Format 1.2 to File Format 1.3.

	//	Multiply by the brightness to get the color that would have been
	//	written into the frame buffer in older versions of KaleidoPaint.
	let theGammaEncodedR = oldBaseR * oldBrightness
	let theGammaEncodedG = oldBaseG * oldBrightness
	let theGammaEncodedB = oldBaseB * oldBrightness

	//	Gamma-decode that color, to get the linear color that newer versions of KaleidoPaint
	//	will submit to the frame buffer (with the understanding that Metal will automatically
	//	gamma-encode that submitted color, because KaleidoPaint now uses an _sRGB pixel format).
	let theLinearR = gammaDecode(theGammaEncodedR)
	let theLinearG = gammaDecode(theGammaEncodedG)
	let theLinearB = gammaDecode(theGammaEncodedB)
	
	//	Factor the linear color into a maximally bright base color along with a brightness.
	let theMaxComponent = max(theLinearR, theLinearG, theLinearB)
	let theLinearBaseR: Double
	let theLinearBaseG: Double
	let theLinearBaseB: Double
	if theMaxComponent > 0.0 {
		let theFactor = 1.0 / theMaxComponent
		theLinearBaseR = theLinearR * theFactor
		theLinearBaseG = theLinearG * theFactor
		theLinearBaseB = theLinearB * theFactor
	} else {	//	the color is black
		//	Let the base color be neutral white
		theLinearBaseR = 1.0
		theLinearBaseG = 1.0
		theLinearBaseB = 1.0
	}
	
	return (theLinearBaseR, theLinearBaseG, theLinearBaseB, theMaxComponent)
}

//	For use when converting from KaleidoPaint File Format 1.3 to 1.4.
func convertColorFromSRGBLinearToP3Linear(
	_ oldBaseR: Double,	//	the old "base color"
	_ oldBaseG: Double,
	_ oldBaseB: Double,
	//	assume a == 1  (that is, opacity α == 1)
	_ oldBrightness: Double
) -> (Double, Double, Double, Double) {	//	returns new (R, G, B, brightness)

	//	Multiply the base color times the brightness to get
	//	the color of interest in Linear sRGB coordinates.
	//	(In principle this would work even with Extended sRGB coordinates,
	//	although in practice previous versions of KaleidoPaint
	//	have supported only non-extended sRGB.)
	let theLinearSRGBColor
		= SIMD3<Double>(oldBaseR, oldBaseG, oldBaseB) * oldBrightness

	//	Convert to Linear Display P3 coordinates.
	let theLinearP3Color = gSRGBtoP3 * theLinearSRGBColor

	//	Factor theLinearP3Color into a maximally bright base color along with a brightness.
	let theNewBrightness = simd_reduce_max(theLinearP3Color)
	let theNewBase = ( theNewBrightness > 0.0 ?
		
			//	color is non-black
			theLinearP3Color / theNewBrightness :
			
			//	color is black, use white as netural base color
			SIMD3<Double>(1.0, 1.0, 1.0)
	)
	
	return (theNewBase[0], theNewBase[1], theNewBase[2], theNewBrightness)
}
