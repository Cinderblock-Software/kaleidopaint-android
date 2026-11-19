//	KaleidoPaintThumbnailProvider.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import QuickLookThumbnailing

enum KaleidoPaintThumbnailError: Error {
	case invalidFileURL
	case invalidUTF8Data
	case invalidDrawingData
	case failedToCreateMetalDevice
	case failedToCreateMetalRenderer
	case failedToRenderImage
}

//	QLThumbnailProvider is nonisolated,
//	so let's make our subclass nonisolated too.
nonisolated class KaleidoPaintThumbnailProvider: QLThumbnailProvider {

	//	Crucial detail:  Our documents' "Uniform Type Identifiers" (UTI)
	//	should be {public.data, public.content}, not {public.plain-text}.
	//	Even though the documents really are plain-text files,
	//	if we declare them as {public.plain-text}, iOS will ignore
	//	our KaleidoPaintThumbnailProvider and instead create thumbnails
	//	showing each drawing's plain-text source code.
	//
	//	Non-obvious pitfall:  iOS apparently caches our documents' UTI
	//	so deeply that changes have no effect.  In particular, if the UTI is set
	//	to {public.plain-text} and iOS is ignoring our KaleidoPaintThumbnailProvider,
	//	then changing the UTI to {public.data, public.content} will have no effect --
	//	the cached {public.plain-text} value will continue to be used,
	//	and iOS will continue to ignore our KaleidoPaintThumbnailProvider.
	//	When I was writing 4D Draw's Draw4DThumbnailProvider,
	//	even deleting the app and rebooting the device didn't help.
	//	To solve this problem, I ended up changing the bundle identifier
	//	(see instructions below), although in retrospect changing
	//	the build number might have been a simpler solution.
	//
	//	Corollary:  Don't switch to the app's permanent bundle ID
	//	until you're 100% sure that your QLThumbnailProvider subclass
	//	is working the way you want it to.
	//
	//	More details:
	//
	//	When migrating from the temporary bundle identifier
	//
	//		org.geometrygames.KaleidoPaint-beta
	//
	//	to the permanent
	//
	//		org.geometrygames.KaleidoPaint-mobile
	//
	//	note that the string 'KaleidoPaint-beta' needs to get changed in 6 places!
	//
	//		Build settings "KaleidoPaint" target
	//			PRODUCT_BUNDLE_IDENTIFIER = org.geometrygames.KaleidoPaint-beta
	//
	//		Build settings "KaleidoPaint Thumbnails" target
	//			PRODUCT_BUNDLE_IDENTIFIER = org.geometrygames.KaleidoPaint-beta.Thumbnails
	//
	//		KaleidoPaintDocument.swift
	//			UTType(exportedAs: "org.geometrygames.KaleidoPaint-beta.drawing")
	//
	//		KaleidoPaint Info.plist
	//			Exported Types Identifiers > Item 0 > Identifiers
	//				org.geometrygames.KaleidoPaint-beta.drawing
	//			Document types > Item 0 > Document Content Type Identifiers > Item 0
	//				KaleidoPaint-beta.drawing
	//
	//		KaleidoPaint Thumbnails Info.plist
	//			NSExtension > NSExtensionAttributes > QLSupportedContentTypes > Item 0
	//			   org.geometrygames.KaleidoPaint-beta.drawing
	//
	//	Search for it and replace them all, or otherwise the thumbnails
	//	won't get properly created.
	//
	//	Reference:  Apple's page
	//
	//		Building a Document Browser App for Custom File Formats
	//	at	https://developer.apple.com/documentation/uikit/view_controllers/building_a_document_browser_app_for_custom_file_formats
	//
	//	shows how to configure a custom file format and provide thumbnails
	//	(and also "previews", which KaleidoPaint doesn't need).
	//	Best of all, that page provide a working Xcode project to use as a model.
	//
	//	The page
	//
	//		https://www.raywenderlich.com/5244-document-based-apps-tutorial-getting-started
	//
	//	also provides some instructions, but they may be less definitive.
	//
	//	Neither the Apple project nor the Ray Wenderlich project
	//	uses SwiftUI, but that may be irrelevant for creating thumbnails.
	
	//	In March 2021
	//
	//	Debugging thumbnails in 4D Draw (and presumably in KaleidoPaint too)
	//	is hit-or-miss.  Sometimes breakpoints and print statements get respected,
	//	sometimes not.
	//
	//	When I trying running the ThumbnailProvider
	//	for Apple's Particles sample code in the debugger,
	//	their ThumbnailProvider crashes entirely (!).

	override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {

		//	If in the future SwiftUI includes a concurrency-friendly
		//	async version of provideThumbnail, maybe I won't need
		//	this synchronous wrapper for a provideThumbnailAsync().

		//	Copy the relevant parameters, to avoid passing a reference
		//	to the QLFileThumbnailRequest into our async Task.
		//
		let theFileURL = request.fileURL
		let theMaximumSize = request.maximumSize
		let theScale = request.scale
		
		//	This provideThumbnail is called from synchronous code,
		//	but KaleidoPaintRenderer() is asynchronous.
		//	So we need to make the jump.
		//
		//	Swift 6 is unwilling to pass the handler into asynchronous code,
		//	to avoid the risk that we might access it here and in the Task
		//	at the same time. As a workaround, let's cast the handler
		//	to be nonisolated.
		//
		//	If Apple someday includes an async version of provideThumbnail,
		//	then our problems are solved. But this might not be a priority
		//	for Apple, if most developers can create thumbnails directly,
		//	in synchronous code, in contrast to our situation where our
		//	computation relies on a renderer that's MainActor-isolated.
		//
		nonisolated(unsafe) let theNonisolatedHandler = handler

		Task() { @Sendable in
		
			let (theThumbnailReply, theError) = await provideThumbnailAsync(
													fileURL: theFileURL,
													maximumSize: theMaximumSize,
													scale: theScale)

			theNonisolatedHandler(theThumbnailReply, theError)
		}
	}
}

nonisolated func provideThumbnailAsync(
	fileURL: URL,
	maximumSize: CGSize,
	scale: CGFloat
) async -> (QLThumbnailReply?, Error?) {

	//	Diagnostic code, to test whether the device is using
	//	the current version of the KaleidoPaintThumbnailProvider
	//	(as opposed to whatever cached version it might have).
//		let theTestDrawingBlock = { () -> Bool in
//			let theColor = UIColor.red	//	change to color for subsequent tests
//			theColor.setFill()
//			let theRect = CGRect(origin: .zero, size: theMaximumSize)
//			UIRectFill(theRect)
//			return true
//		}
//		let theTestReply = QLThumbnailReply(
//			contextSize: theMaximumSize,
//			currentContextDrawing: theTestDrawingBlock)
//		handler(theTestReply, nil)
//		return

	//	Load the ModelData.

	let theDrawingAsUTF8EncodedData: Data
	do {
		theDrawingAsUTF8EncodedData = try Data(contentsOf: fileURL )
	} catch {
		return (nil, KaleidoPaintThumbnailError.invalidFileURL)
	}

	guard let theDrawingAsText = String(
							data: theDrawingAsUTF8EncodedData,
							encoding: .utf8
	) else {
		return (nil, KaleidoPaintThumbnailError.invalidUTF8Data)
	}
	
	let theDocument: KaleidoPaintDocument
	do {
		theDocument = try await KaleidoPaintDocument(drawingAsText: theDrawingAsText)
	} catch {
		return (nil, KaleidoPaintThumbnailError.invalidDrawingData)
	}

	//	Adjust itsUnitCellPlacement so that the thumbnail contains
	//	only a few copies of the unit cell.
	let theNumCopiesOfUnitCell = 2.0	//	purely an aesthetic preference

	let theOldArea = await
		theDocument.itsUnitCellPlacement.itsTranslations.determinant
	if theOldArea <= 0.0 {
		return (nil, KaleidoPaintThumbnailError.invalidDrawingData)
	}
	
	//	As explained in the comment on "Coordinate systems" at the top
	//	of the file KaleidoPaintCoordinateSystems.swift,
	//	the length of the page rectangle's diagonal is always
	//	exactly 1 in drawing coordinates.  Thus when drawing
	//	a square thumbnail, each side of the square will have length √½,
	//	and the image will have area 1/2 in drawing coordinates.
	//
	let theNewArea = 0.5 / theNumCopiesOfUnitCell
	let theFactor = sqrt( theNewArea / theOldArea )
	await theDocument.mutateUnitCellPlacement(
		corner: SIMD2<Double>.zero,	//	arbitrary choice
		translationsMultiplier: theFactor)

	//	Compute the size of the largest valid square image.
//		let theMinDimensionPt = min(theMaximumSize.width,
//									theMaximumSize.height)
//		let theMinDimensionPx = theMinDimensionPt * theScale
	let theContextSizePt = maximumSize
	let theContextSizePx = CGSize(	width:  theContextSizePt.width  * scale,
									height: theContextSizePt.height * scale)
	
	//	Create a KaleidoPaintRenderer.

	//	There are two reasons to set isDrawingThumbnail = true .
	//
	//	---------------------------------------
	//	Reason #1
	//
	//	When QuickLook calls our callback code (theDrawingBlock - see below),
	//	it provides a CGContext with only a "narrow gamut" color space.
	//	If we rendered a Display P3 image, then when context.draw(in:)
	//	draws it, it would screw up the colors (more precisely,
	//	the specular highlights would all come out dark, and of the wrong hue).
	//	To avoid that, we must render a narrow-color thumbnail image.
	//
	//		Note:  The fragment function will nevertheless
	//		compute wide-gamut Extended Range sRGB colors,
	//		but Metal will clamp those colors to non-extended-range sRGB
	//		when it writes them into the framebuffer.
	//
	//	---------------------------------------
	//	Reason #2
	//
	//	KaleidoPaintRenderer needs to set itsUnitCellSize = 512
	//	when rendering thumbnails.  See comment in KaleidoPaintRenderer.init?().
	//	---------------------------------------

	guard let theRenderer = await KaleidoPaintRenderer(
	
		//	With log2UnitCellResolution = 9, SwiftUI draws
		//	almost all the thumbnails immediately.
		//
		//	With log2UnitCellResolution = 10, it draws
		//	them grudgingly, as you open and close each drawing.
		//
		//	Either way, the most complicated drawings
		//	will time out, and SwiftUI will use
		//	a generic document thumbnail instead.
		//
		log2UnitCellResolution: 9,	//	=> unit cell size = 2^9 = 512
		isDrawingThumbnail: true
	) else {
		return (nil, KaleidoPaintThumbnailError.failedToCreateMetalRenderer)
	}

	//	Ask theRenderer to create a screenshot for us.
	guard let theCGImage = await theRenderer.createOffscreenImage(
		modelData: theDocument,
		widthPx:  Int(theContextSizePx.width ),
		heightPx: Int(theContextSizePx.height),
		transparentBackground: false,
		extraRenderFlag: nil
	) else {
		return (nil, KaleidoPaintThumbnailError.failedToRenderImage)
	}

	//	Later on, when QuickLook wants to draw the thumbnail,
	//	it will prepare a Core Graphics drawing context
	//	of size theContextSizePx (not theContextSizePt!)
	//	and call our code (theDrawingBlock).
	//
	//		Note:  QuickLook will set up the drawing context
	//		with Core Graphics' coordinate system,
	//		meaning that the origin at the lower left
	//		and the y axis is directed upward.
	//
	let theDrawingBlock = { (context: CGContext) -> Bool in

		//	Diagnostic code to check whether the context
		//	supports wide-gamut color or not.
		//	iOS 14.4.1, running on my iPhone SE (2020)
		//	provides a narrow-gamut context, even though
		//	the phone has a Display P3 display.
		//
		//		if let theColorSpace = context.colorSpace {
		//			print(theColorSpace.isWideGamutRGB ? "wide gamut" : "narrow gamut")
		//		} else {
		//			print("no color space")
		//		}
		//

		//	Draw the screenshot in the graphics context
		//	that QuickLook as prepared for us.
		//
		//		Note:  draw(in:) draws theCGImage
		//		"in current user space coordinates",
		//		which empirically seem to be points, not pixels.
		//		So to fill the available space, we must
		//		pass theContextSizePx, not theContextSizePt.
		//
		context.draw(
			theCGImage,
			in: CGRect(origin: .zero, size: theContextSizePx))

		//	Return true iff the thumbnail was
		//	successfully drawn inside this block.
		return true
	}

	let theReply = QLThumbnailReply(
		contextSize: theContextSizePt,	//	in points, not pixels
		drawing: theDrawingBlock)		//	uses pixels, not points

	return (theReply, nil)
}
