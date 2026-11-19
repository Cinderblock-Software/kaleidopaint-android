//	KaleidoPaintRenderer.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import Metal


//	Approximate the unit circle as a regular polygon,
//	rendered as a triangle strip.
let gUnitCircleVertices: [SIMD2<Double>] = {

	//	theVertexCount ≡ 2 (mod 4) so that a half-dot may
	//	include the vertices at (0,+1) and (0,-1), while placing
	//	all vertex pairs symmetrically across the x-axis.
	let theVertexCount = 22
	let theVertexPairCount = theVertexCount / 2
	let theAngleIncrement = 2.0 * Double.pi / Double(theVertexCount)

	var theVertices = [SIMD2<Double>](
						repeating: SIMD2<Double>.zero,
						count: theVertexCount)
	
	//	List the unit circle's vertices in an order suitable
	//	for rendering a dot as a triangle strip.
	for i in 0 ..< theVertexPairCount {
	
		let theAngle  = (0.5 + Double(i)) * theAngleIncrement
		let theCosine = cos(theAngle)
		let theSine   = sin(theAngle)
		
		theVertices[2*i + 0] = SIMD2<Double>(theCosine, +theSine)
		theVertices[2*i + 1] = SIMD2<Double>(theCosine, -theSine)
	}
	
	return theVertices
}()
let gUnitCircleVertexCount = gUnitCircleVertices.count

//	The half-circle is the "eastern" half of the unit circle.
let gUnitHalfCircleVertexCount = gUnitCircleVertexCount/2 + 1

let gRawControlHandleVertices: [SIMD2<Double>] = [
	
		SIMD2<Double>(-1.0, -1.0),
		SIMD2<Double>(+1.0, -1.0),
		SIMD2<Double>(-1.0, +1.0),
		SIMD2<Double>(+1.0, +1.0)
	]
let gControlHandleVertexCount = gRawControlHandleVertices.count


class KaleidoPaintRenderer: GeometryGamesRenderer<KaleidoPaintDocument> {

	//	Before calling the superclass's (GeometryGamesRenderer's) init()
	//	to set up itsDevice, itsColorPixelFormat, itsCommandQueue, etc.,
	//	and indeed even before calling any of our own methods to set up
	//	pipeline states, buffers, textures, etc., we must ensure that
	//	all our instances variables have values.  For that reason,
	//	we declare them to be optionals, which are automatically initialized
	//	to nil.  On the other hand, unwrapping such optionals quickly
	//	becomes tedious, and makes the code harder to read.
	//	So let's define them as implicitly unwrapped optionals.
	//	I'm slightly uncomfortable using implicitly unwrapped optionals
	//	-- I hadn't intended to use them at all, for run-time safety --
	//	but in this case all we need to do to avoid problems is make sure
	//	that our own init() function provides non-nil values for these
	//	instances variables before returning.

	var itsPageRectangleRenderPipelineState: MTLRenderPipelineState!
	var itsTriStripRenderPipelineState: MTLRenderPipelineState!
	var itsTriStripCBSRenderPipelineState: MTLRenderPipelineState!
	var itsControlHandleRenderPipelineState: MTLRenderPipelineState!

	var itsFloodFillSetUpQueueComputePipelineState: MTLComputePipelineState!
	var itsFloodFillProcessQueueComputePipelineState: MTLComputePipelineState!
	var itsFloodFillAssignScratchRowsComputePipelineState: MTLComputePipelineState!
	var itsFloodFillSingleToWholeComputePipelineState: MTLComputePipelineState!
	var itsFloodFillFromMaskComputePipelineState: MTLComputePipelineState!
	var itsOneLayerCompositionComputePipelineState: MTLComputePipelineState!
	var itsTwoLayerCompositionComputePipelineState: MTLComputePipelineState!
	var itsThreeLayerCompositionComputePipelineState: MTLComputePipelineState!

	var itsFloodFillQueueBuffer: MTLBuffer!
	var itsFloodFillInterCallBuffer: MTLBuffer!
	var itsSingleFillScratchBuffer: MTLBuffer!
	var itsSingleFillScratchBufferRunCountsScratchBuffer: MTLBuffer!
	var itsWholeDrawingScratchBuffer: MTLBuffer!
	var itsWholeDrawingScratchBufferWriteIndexBuffer: MTLBuffer!
	var itsRowWriteIndexScratchBuffer: MTLBuffer!
	var itsRLEPaddingBuffer: MTLBuffer!

	var itsUnitCellSymmetriesBufferPool: GeometryGamesBufferPool!

	var itsUnitCellBaseDrawingTexture: MTLTexture!		//	Display P3
	var itsUnitCellCurveInProgressTexture: MTLTexture!	//	Display P3
	var itsUnitCellSingularitiesTexture: MTLTexture!	//	Display P3
	var itsUnitCellComposedTexture: MTLTexture!			//	Extended Range sRGB
														//		(or non-Extended Range
														//		on non-P3 devices)

	//	The KaleidoPaintDocument will increment
	//
	//		its…Texture…RequestCount
	//
	//	whenever it wants us to redraw one of our unit cell textures.
	//	When we update the texture, we'll set our own
	//
	//		its…Texture…RedrawCount
	//
	//	to match the …RequestCount, so we'll be be able
	//	to tell when the next request arrives.
	//
	var itsBaseDrawingTextureFullRedrawCount: Int = 0
	var itsBaseDrawingTextureLastElementCount: Int = 0
	var itsCurveInProgressTextureRedrawCount: Int = 0
	var itsSingularitiesTextureRedrawCount: Int = 0
	var itsCompositeTextureRedrawCount: Int = 0
	
	var itsSamplerState: MTLSamplerState!

	let itsUnitCellSize: Int
	let itsIntermediatePixelFormat: MTLPixelFormat
	let itsComposedPixelFormat: MTLPixelFormat

	let itsEightWayFloodFillFlag: Bool	//	true for 8-way flood fill, false for 4-way flood fill
	let itsWholeDrawingScratchBufferLength: UInt32	//	Buffer length in RLERuns (not bytes)
	
	//	page corners
	
	struct PageCornerVertexData {
		var viewCoords: SIMD2<Float>
		var drawingCoords: SIMD2<Float>	//	= (±w/2, ±h/2), included for conceptual clarity,
										//		but not needed in GPU vertex function
		var extendedUnitCellCoords: SIMD2<Float>
	}
	
	//	unit cell textures

	enum UnitCellTextureType {
		
		case forRender				//	no mipmaps, no access as MTLBuffer
		case forRenderAndFloodFill	//	no mipmaps, but with access as MTLBuffer
		case forSampling			//	with mipmaps, for sampling but not for use as render target
	}
	

	//	control handles

	struct ControlHandleVertexData {
		
		var	pos: SIMD2<Float>	//	position (x,y) in unit cell coordinates;
								//		see details in KPControlHandleVertexFunction()
		var tex: SIMD2<Float>	//	texture coordinates (±1.0, ±1.0)
	}
	

	init?(
		log2UnitCellResolution: Int,
		isDrawingThumbnail: Bool = false
	) {

		itsUnitCellSize // = 2^(log2UnitCellResolution)
						   = 1 << log2UnitCellResolution

		//	Intermediate unit cell textures pixel format
		//
		//	The pixel format for the three intermediate textures
		//
		//		unitCellBaseDrawing
		//		unitCellCurveInProgress
		//		unitCellSingularities
		//
		//	is a little delicate.  On the one hand, these textures need
		//	an alpha channel so that they may be composited together to give
		//
		//		unitCellComposed
		//
		//	On the other hand, the pixel format can be at most 32-bit,
		//	because the flood fill algorithm runs on the GPU, which
		//	supports at most uint32_t input buffers.
		//	So some version of BRGA8 is the only reasonable choice.
		//
		//	A gamma-encoded format (with "_sRGB" suffix) would make
		//	slightly better use of the available color space, while
		//	a linear format (without "_sRGB" suffix) might be slightly
		//	more efficient because no encoding/decoding would be required.
		//	My guess is that both of those "advantages" are negligible
		//	(in particular, KaleidoPaint uses no color gradients,
		//	so there's no risk of "banding").  Essentially on a whim,
		//	I decided to use the linear format.
		//
		//		Note #1:  All devices that run iOS 13 have A8 processors or higher,
		//		which belong to MTLGPUFamilyApple2, which lets a GPU compute function
		//		write to a gamma-encoded pixel format (with _sRGB suffix)
		//		as well as a linear pixel format (no _sRGB suffix).
		//
		//		Note #2:  There's no need for itsIntermediatePixelFormat
		//		to support values outside the range [0.0, 1.0],  because
		//		we draw into the intermediate textures in Display P3 coordinates.
		//		The GPU function KPLayerCompositionComputeFunction()
		//		will convert from Display P3 coordinates to Extended-Range sRGB coordinates
		//		just after it combines the values from the three intermediate textures.
		//
		itsIntermediatePixelFormat = MTLPixelFormat.bgra8Unorm

		//	Composed unit cell texture pixel format
		if gMainScreenSupportsP3 {
			
			//	The pixel format for the
			//
			//		unitCellComposed
			//
			//	texture needs to support negative values (for Extended-Range sRGB coordinates)
			//	and also needs to be writable from the GPU compute function
			//	that does the compositing.
			//
			//	2022-07-26  We also require that this pixel format support transparency,
			//	to allow for exporting images with a transparent background.
			//
			//	All devices with Wide Color (P3) displays have A9 processors or higher,
			//	which belong to MTLGPUFamilyApple3, which fully supports
			//	all the extended range pixel formats.

			//	64-bit format, gamma-encoded (_sRGB) or linear (without _sRGB) is OK
			itsComposedPixelFormat = MTLPixelFormat.bgra10_xr
			
		} else {
		
			//	All devices that run iOS 13 have A8 processors or higher, which
			//	belong to MTLGPUFamilyApple2, which lets a GPU compute function
			//	write to a gamma-encoded pixel format (with _sRGB suffix)
			//	as well as a linear pixel format (no _sRGB suffix).
			//
			//	There's no need to support negative values
			//	when rendering to a Narrow Color (sRGB gamut) display.
			//
			itsComposedPixelFormat = MTLPixelFormat.bgra8Unorm
		}
		//	Another possibility, suitable for all GPU families, but requiring 64 bits/pixel
		//		itsComposedPixelFormat = MTLPixelFormat.rgba16Float

		//	In the flood fill algorithm, should paint flow only
		//	to a pixel's four nearest neighbors
		//
		//		┌───┬───┬───┐
		//		│   │   │   │
		//		├───┼─↑─┼───┤
		//		│   ← * →   │
		//		├───┼─↓─┼───┤
		//		│   │   │   │
		//		└───┴───┴───┘
		//
		//	or also to the pixels along the diagonals
		//
		//		┌───┬───┬───┐
		//		│   │   │   │
		//		├───╲─↑─╱───┤
		//		│   ← * →   │
		//		├───╱─↓─╲───┤
		//		│   │   │   │
		//		└───┴───┴───┘
		//
		//	?
		//
		//	Note:
		//		Unlike with the old single-pixel-based flood fill algorithm,
		//		with the new run-based flood fill algorithm, the performance
		//		difference between 4- and 8-way flood filling is negligible.
		//		On my iPad Air 2 running iOS 10.3.3, the initial rendering
		//		of Francine Champagne's "Mmmm... cookies" took 1.11 and 1.12 seconds,
		//		respectively, which are equal to within the precision of the measurement.
		//
		//	The advantage of 4-way flood fill is that it avoids
		//	leakage through thin lines, but its disadvantage
		//	is that it sometimes leaves unfilled "orphan" pixels
		//	where lines intersect at sharp angles.  For an example
		//	of the latter, given the two lines shown below (marked
		//	with '*' and '#' respectively) if we start a flood fill
		//	at the top right, it will fail to reach the center pixel.
		//
		//			- - # - -
		//			- # # - -
		//			- # - * *
		//			# * * * -
		//			* * - - -
		//
		//	When log2UnitCellResolution = 10 (medium resolution)
		//	or 11 (high resolution), we use 8-way flood fill
		//	to avoid the aforementioned orphan pixels.
		//
		//	When log2UnitCellResolution = 9 (low resolution) --
		//	which includes the extra-important case of drawing thumbnails,
		//	which use low resolution to avoid getting timed out --
		//	we have two options
		//
		//		we could use 8-way flood filling to avoid ophaning pixels
		//			but with a higher value for minLog2ThicknessFactor
		//			to avoid leakage, or
		//
		//		we could use 4-way flood filling and accept occasional orphan pixels
		//			to allow a lower value for minLog2ThicknessFactor
		//			while still avoiding leakage.
		//
		//	We choose the second option (4-way flood fill) because
		//	supporting thinner lines is more important than rendering
		//	pixel-perfect images at low resolution.  As mentioned above,
		//	the medium- and high-resolution images will avoid orphaning pixels.
		//
		itsEightWayFloodFillFlag = (log2UnitCellResolution >= 10)
		
		itsWholeDrawingScratchBufferLength = UInt32(1000 * itsUnitCellSize)	//	number of RLERuns (not bytes)

		super.init(
			wantsMultisampling: false,	//	KaleidoPaint requires no multisampling
			wantsDepthBuffer: false,	//	KaleidoPaint requires no depth buffer
				//	Specify color values in linear extended-range sRGB.
				//	This yellow clearColor should never get seen.
			clearColor: MTLClearColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0),
			isDrawingThumbnail: isDrawingThumbnail)

		if !(
			self.setUpPipelineStates()
		 && self.setUpFixedBuffers()
		 && self.setUpInflightBufferPools()
		 && self.setUpTextures()
		 && self.setUpSamplerStates()
		) {
			assertionFailure("Unable to set up Metal resources")
			return nil
		}
	}

	// MARK: -
	// MARK: graphics setup

	func setUpPipelineStates() -> Bool {

		guard let theGPUFunctionLibrary = itsDevice.makeDefaultLibrary() else {
			assertionFailure("Failed to create default GPU function library")
			return false
		}
		
		guard let theGPUPageRectangleVertexFunction
		= theGPUFunctionLibrary.makeFunction(name: "KPPageRectangleVertexFunction") else {
			assertionFailure("KPPageRectangleVertexFunction not found")
			return false
		}
		guard let theGPUPageRectangleFragmentFunction
		= theGPUFunctionLibrary.makeFunction(name: "KPPageRectangleFragmentFunction") else {
			assertionFailure("KPPageRectangleFragmentFunction not found")
			return false
		}

		//	Apple's documentation for MTLFunctionConstantValues says that
		//
		//		A single MTLFunctionConstantValues object can be applied
		//		to multiple MTLFunction objects (for example, a vertex function
		//		and a fragment function). After a specialized function has been created,
		//		any changes to its constant values have no further effect on it.
		//		However, you can reset, add, or modify any constant values
		//		in the MTLFunctionConstantValues object and reuse it
		//		to create another MTLFunction object.
		//
		var theFalseValue: Bool = false	//	Declare these as mutable variables ("var") so that
		var theTrueValue: Bool  = true	//		we may pass their addresses to setConstantValue().
		let theCompileTimeConstants = MTLFunctionConstantValues()

		theCompileTimeConstants.setConstantValue(
			&theFalseValue,
			type: .bool,
			withName: "gColorBySymmetry")
		let theGPUTriStripVertexFunction: MTLFunction
		do {
			theGPUTriStripVertexFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPTriStripVertexFunction", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}
		let theGPUTriStripFragmentFunction: MTLFunction
		do {
			theGPUTriStripFragmentFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPTriStripFragmentFunction", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}
		
		theCompileTimeConstants.setConstantValue(
			&theTrueValue,
			type: .bool,
			withName: "gColorBySymmetry")
		let theGPUTriStripCBSVertexFunction: MTLFunction
		do {
			theGPUTriStripCBSVertexFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPTriStripVertexFunction", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}
		let theGPUTriStripCBSFragmentFunction: MTLFunction
		do {
			theGPUTriStripCBSFragmentFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPTriStripFragmentFunction", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}

		guard let theGPUControlHandleVertexFunction
		= theGPUFunctionLibrary.makeFunction(name: "KPControlHandleVertexFunction") else {
			assertionFailure("KPControlHandleVertexFunction not found")
			return false
		}
		guard let theGPUControlHandleFragmentFunction
		= theGPUFunctionLibrary.makeFunction(name: "KPControlHandleFragmentFunction") else {
			assertionFailure("KPControlHandleFragmentFunction not found")
			return false
		}
		
		theCompileTimeConstants.reset()
		//	Copy values from immutable constants ("let") to mutable variables ("var")
		//	so that we may pass their addresses to setConstantValue().
		var theUnitCellSize: UInt32 = UInt32(itsUnitCellSize)
		var theWholeDrawingScratchBufferLength: UInt32	= itsWholeDrawingScratchBufferLength
		var theEightWayFloodFillFlag: Bool = itsEightWayFloodFillFlag
		theCompileTimeConstants.setConstantValue(
			&theUnitCellSize,
			type: .uint,
			withName: "gUnitCellSize")
		theCompileTimeConstants.setConstantValue(
			&theWholeDrawingScratchBufferLength,
			type: .uint,
			withName: "gRLEScratchBufferLength")
		theCompileTimeConstants.setConstantValue(
			&theEightWayFloodFillFlag,
			type: .bool,
			withName: "gEightWayFloodFillFlag")
		let theGPUFloodFillSetUpQueueComputeFunction: MTLFunction
		do {
			theGPUFloodFillSetUpQueueComputeFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPFloodFillSetUpQueueComputeFunction", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}
		let theGPUFloodFillProcessQueueComputeFunction: MTLFunction
		do {
			theGPUFloodFillProcessQueueComputeFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPFloodFillProcessQueueComputeFunction", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}
		let theGPUFloodFillAssignIndicesComputeFunction: MTLFunction
		do {
			theGPUFloodFillAssignIndicesComputeFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPFloodFillAssignWholeDrawingScratchBufferWriteIndices", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}
		let theGPUFloodFillSingleToWholeComputeFunction: MTLFunction
		do {
			theGPUFloodFillSingleToWholeComputeFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPFloodFillSingleFillToWholeDrawingComputeFunction", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}
		let theGPUFloodFillFromMaskComputeFunction: MTLFunction
		do {
			theGPUFloodFillFromMaskComputeFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPFloodFillFromMaskComputeFunction", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}
		
		theCompileTimeConstants.reset()
		theCompileTimeConstants.setConstantValue(
			&theTrueValue,
			type: .bool,
			withName: "gComposeWithFirstLayer")
		theCompileTimeConstants.setConstantValue(
			&theFalseValue,
			type: .bool,
			withName: "gComposeWithSecondLayer")
		theCompileTimeConstants.setConstantValue(
			&theFalseValue,
			type: .bool,
			withName: "gComposeWithThirdLayer")
		let theGPU1LayerCompositionComputeFunction: MTLFunction
		do {
			theGPU1LayerCompositionComputeFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPLayerCompositionComputeFunction", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}
		theCompileTimeConstants.setConstantValue(
			&theTrueValue,
			type: .bool,
			withName: "gComposeWithSecondLayer")
		let theGPU2LayerCompositionComputeFunction: MTLFunction
		do {
			theGPU2LayerCompositionComputeFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPLayerCompositionComputeFunction", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}
		theCompileTimeConstants.setConstantValue(
			&theTrueValue,
			type: .bool,
			withName: "gComposeWithThirdLayer")
		let theGPU3LayerCompositionComputeFunction: MTLFunction
		do {
			theGPU3LayerCompositionComputeFunction = try theGPUFunctionLibrary.makeFunction(
				name: "KPLayerCompositionComputeFunction", constantValues: theCompileTimeConstants)
		} catch {
			assertionFailure("setUpPipelineStates error: " + error.localizedDescription)
			return false
		}
		
		
		//	Page rectangle
		
		let thePageRectangleVertexDescriptor = MTLVertexDescriptor()
		
			//	Say where to find each attribute.
		
		guard let theViewCoordsOffset = MemoryLayout.offset(of: \PageCornerVertexData.viewCoords) else {
			assertionFailure("Failed to find offset of PageCornerVertexData.viewCoords")
			return false
		}
		thePageRectangleVertexDescriptor.attributes[VertexAttributePRViewCoords].format = MTLVertexFormat.float2
		thePageRectangleVertexDescriptor.attributes[VertexAttributePRViewCoords].bufferIndex = BufferIndexVFVertexAttributes
		thePageRectangleVertexDescriptor.attributes[VertexAttributePRViewCoords].offset = theViewCoordsOffset
		
		guard let theExtUnitCellCoordsOffset = MemoryLayout.offset(of: \PageCornerVertexData.extendedUnitCellCoords) else {
			assertionFailure("Failed to find offset of PageCornerVertexData.extendedUnitCellCoords")
			return false
		}
		thePageRectangleVertexDescriptor.attributes[VertexAttributePRExtendedUnitCellCoords].format = MTLVertexFormat.float2
		thePageRectangleVertexDescriptor.attributes[VertexAttributePRExtendedUnitCellCoords].bufferIndex = BufferIndexVFVertexAttributes
		thePageRectangleVertexDescriptor.attributes[VertexAttributePRExtendedUnitCellCoords].offset = theExtUnitCellCoordsOffset

			//	Say how to step through each buffer.
		
		thePageRectangleVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stepFunction = MTLVertexStepFunction.perVertex
		thePageRectangleVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stride = MemoryLayout<PageCornerVertexData>.stride
		
		//	Create thePageRectanglePipelineDescriptor and attach thePageRectangleVertexDescriptor.

		let thePageRectanglePipelineDescriptor = MTLRenderPipelineDescriptor()
		thePageRectanglePipelineDescriptor.label = "KaleidoPaint page rectangle render pipeline"
		thePageRectanglePipelineDescriptor.vertexFunction = theGPUPageRectangleVertexFunction
		thePageRectanglePipelineDescriptor.fragmentFunction = theGPUPageRectangleFragmentFunction
		thePageRectanglePipelineDescriptor.vertexDescriptor = thePageRectangleVertexDescriptor
		thePageRectanglePipelineDescriptor.colorAttachments[0].pixelFormat = itsColorPixelFormat
		thePageRectanglePipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
		
		do {
			itsPageRectangleRenderPipelineState = try itsDevice.makeRenderPipelineState(descriptor: thePageRectanglePipelineDescriptor)	//	returns non-nil
		} catch {
			assertionFailure("Couldn't create itsPageRectangleRenderPipelineState: \(error)")
			return false
		}
		
		
		//	Triangle strips
		
		//		normal use
		
		let theTriStripVertexDescriptor = MTLVertexDescriptor()
		
		theTriStripVertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormat.float2
		theTriStripVertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexVFVertexAttributes
		theTriStripVertexDescriptor.attributes[VertexAttributePosition].offset = 0
		
		theTriStripVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stepFunction = MTLVertexStepFunction.perVertex
		theTriStripVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stride = MemoryLayout<SIMD2<Float>>.stride
		
		let theTriStripPipelineDescriptor = MTLRenderPipelineDescriptor()
		theTriStripPipelineDescriptor.label = "KaleidoPaint triangle strip render pipeline"
		theTriStripPipelineDescriptor.vertexFunction = theGPUTriStripVertexFunction
		theTriStripPipelineDescriptor.fragmentFunction = theGPUTriStripFragmentFunction
		theTriStripPipelineDescriptor.vertexDescriptor = theTriStripVertexDescriptor
		theTriStripPipelineDescriptor.colorAttachments[0].pixelFormat = itsIntermediatePixelFormat
		theTriStripPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
		
		do {
			itsTriStripRenderPipelineState = try itsDevice.makeRenderPipelineState(descriptor: theTriStripPipelineDescriptor)	//	returns non-nil
		} catch {
			assertionFailure("Couldn't create itsTriStripRenderPipelineState: \(error)")
			return false
		}
		
		//		color-by-symmetry
		
		let theTriStripCBSVertexDescriptor = MTLVertexDescriptor()
		
		theTriStripCBSVertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormat.float2
		theTriStripCBSVertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexVFVertexAttributes
		theTriStripCBSVertexDescriptor.attributes[VertexAttributePosition].offset = 0
		
		theTriStripCBSVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stepFunction = MTLVertexStepFunction.perVertex
		theTriStripCBSVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stride = MemoryLayout<SIMD2<Float>>.stride
		
		let theTriStripCBSPipelineDescriptor = MTLRenderPipelineDescriptor()
		theTriStripCBSPipelineDescriptor.label = "KaleidoPaint triangle strip color-by-symmetry render pipeline"
		theTriStripCBSPipelineDescriptor.vertexFunction = theGPUTriStripCBSVertexFunction
		theTriStripCBSPipelineDescriptor.fragmentFunction = theGPUTriStripCBSFragmentFunction
		theTriStripCBSPipelineDescriptor.vertexDescriptor = theTriStripCBSVertexDescriptor
		theTriStripCBSPipelineDescriptor.colorAttachments[0].pixelFormat = itsIntermediatePixelFormat
		theTriStripCBSPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
		
		do {
			itsTriStripCBSRenderPipelineState = try itsDevice.makeRenderPipelineState(descriptor: theTriStripCBSPipelineDescriptor)	//	returns non-nil
		} catch {
			assertionFailure("Couldn't create itsTriStripCBSRenderPipelineState: \(error)")
			return false
		}
		
		
		//	Control handles
		
		let theControlHandleVertexDescriptor = MTLVertexDescriptor()
		
		guard let theControlHandlePosOffset = MemoryLayout.offset(of: \ControlHandleVertexData.pos) else {
			assertionFailure("Failed to find offset of ControlHandleVertexData.pos")
			return false
		}
		theControlHandleVertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormat.float2
		theControlHandleVertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexVFVertexAttributes
		theControlHandleVertexDescriptor.attributes[VertexAttributePosition].offset = theControlHandlePosOffset
		
		guard let theControlHandleTexOffset = MemoryLayout.offset(of: \ControlHandleVertexData.tex) else {
			assertionFailure("Failed to find offset of ControlHandleVertexData.tex")
			return false
		}
		theControlHandleVertexDescriptor.attributes[VertexAttributeTexCoords].format = MTLVertexFormat.float2
		theControlHandleVertexDescriptor.attributes[VertexAttributeTexCoords].bufferIndex = BufferIndexVFVertexAttributes
		theControlHandleVertexDescriptor.attributes[VertexAttributeTexCoords].offset = theControlHandleTexOffset
		
		theControlHandleVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stepFunction = MTLVertexStepFunction.perVertex
		theControlHandleVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stride = MemoryLayout<ControlHandleVertexData>.stride
		
		let theControlHandlePipelineDescriptor = MTLRenderPipelineDescriptor()
		theControlHandlePipelineDescriptor.label = "KaleidoPaint control handle render pipeline"
		theControlHandlePipelineDescriptor.vertexFunction = theGPUControlHandleVertexFunction
		theControlHandlePipelineDescriptor.fragmentFunction = theGPUControlHandleFragmentFunction
		theControlHandlePipelineDescriptor.vertexDescriptor = theControlHandleVertexDescriptor
		theControlHandlePipelineDescriptor.colorAttachments[0].pixelFormat = itsIntermediatePixelFormat
		//
		//	Alpha blending
		//
		//	The comment accompanying the definition of PREMULTIPLY_RGBA()
		//	explains the (1, 1 - α) blend factors.
		//
		//	KaleidoPaint uses alpha-blending only for the control handles,
		//	to get them to look smoother (not too pixelated) at small sizes.
		//	(Recall that KaleidoPaint's unit cell doesn't use multisampling,
		//	because the flood-fill algorithm needs distinct edges.)
		//
		//	In 3D apps with a lot of overdraw, alpha blending can
		//	reduce performance on iOS because it forces
		//	the tile-based deferred renderer to render all fragments,
		//	not just the "topmost" fragment for each pixel.
		//	For KaleidoPaint's control handles, though,
		//	this isn't an issue, because we're happy to draw
		//	all the control handles, in the order they get submitted.
		//
		theControlHandlePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
		theControlHandlePipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
		theControlHandlePipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperation.add
		theControlHandlePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.one
		theControlHandlePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.one
		theControlHandlePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
		theControlHandlePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.oneMinusSourceAlpha

		do {
			itsControlHandleRenderPipelineState = try itsDevice.makeRenderPipelineState(descriptor: theControlHandlePipelineDescriptor)	//	returns non-nil
		} catch {
			assertionFailure("Couldn't create itsControlHandleRenderPipelineState: \(error)")
			return false
		}
		
		
		//	Flood fills
		
		//	For some of the compute functions we can guarantee that
		//	the threadgroup size is a multiple of the thread execution width,
		//	but only if the threadgroup size is KP_THREAD_EXECUTION_WIDTH ( = 32 ).
		//	I'm pretty sure this is true for all Apple Silicon GPUs as of August 2022.
		//	If Apple someday releases GPUs with a larger thread execution width,
		//	then on those GPUs our threadgroup sizes might no longer be multiples
		//	of the thread execution width.
		//
		//	Even though the threadExecutionWidth is a hardware constant,
		//	we nevertheless need to create a test pipeline state
		//	to find out what it is.
		let theThreadExecutionWidthIsAsExpected: Bool
		do {
			let theTestPipelineState = try itsDevice.makeComputePipelineState(
				function: theGPUFloodFillSetUpQueueComputeFunction)
			
			//	Is the thread execution width what we're expecting?  ( = 32 )
			theThreadExecutionWidthIsAsExpected
				= (theTestPipelineState.threadExecutionWidth == KP_THREAD_EXECUTION_WIDTH)
				
		} catch {
			assertionFailure("Couldn't create theTestPipelineState: \(error)")
			return false
		}

		//	Note:  When we didn't want to set
		//
		//		threadGroupSizeIsMultipleOfThreadExecutionWidth,
		//
		//	we don't need to create a MTLComputePipelineDescriptor at all.
		//	We can instead call the simpler function
		//
		//		tsDevice.makeComputePipelineState(function: the<SOMETHING>ComputeFunction)
		//

		do {
			let theDescriptor = MTLComputePipelineDescriptor()
			theDescriptor.computeFunction
				= theGPUFloodFillSetUpQueueComputeFunction
			theDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth
				= theThreadExecutionWidthIsAsExpected

			itsFloodFillSetUpQueueComputePipelineState
				= try itsDevice.makeComputePipelineState(
					descriptor: theDescriptor,
					options: MTLPipelineOption(),
					reflection: nil)
		} catch {
			assertionFailure("Couldn't create itsFloodFillSetUpQueueComputePipelineState: \(error)")
			return false
		}

		do {
			let theDescriptor = MTLComputePipelineDescriptor()
			theDescriptor.computeFunction
				= theGPUFloodFillProcessQueueComputeFunction
			theDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth
				= theThreadExecutionWidthIsAsExpected

			itsFloodFillProcessQueueComputePipelineState
				= try itsDevice.makeComputePipelineState(
					descriptor: theDescriptor,
					options: MTLPipelineOption(),
					reflection: nil)
		} catch {
			assertionFailure("Couldn't create itsFloodFillProcessQueueComputePipelineState: \(error)")
			return false
		}

		do {
		
			//	The assign scratch rows compute function will run on a single thread.
			//	Definitely not a multiple of the thread execution width!
			
			itsFloodFillAssignScratchRowsComputePipelineState = try itsDevice.makeComputePipelineState(
				function: theGPUFloodFillAssignIndicesComputeFunction)
				
		} catch {
			assertionFailure("Couldn't create itsFloodFillAssignScratchRowsComputePipelineState: \(error)")
			return false
		}

		do {
			//	On newer hardware there'll be maxTotalThreadsPerThreadgroup threads per threadgroup.
			//	It's likely that in practice the thread group size
			//	will often (always?) be a multiple of the thread execution width,
			//	but I don't have a documented proof of that,
			//	so let's not rely on that assumption.
			
			itsFloodFillSingleToWholeComputePipelineState = try itsDevice.makeComputePipelineState(
				function: theGPUFloodFillSingleToWholeComputeFunction)
		} catch {
			assertionFailure("Couldn't create itsFloodFillSingleToWholeComputePipelineState: \(error)")
			return false
		}

		do {
			//	On newer hardware there'll be maxTotalThreadsPerThreadgroup threads per threadgroup.
			//	It's likely that in practice the thread group size
			//	will often (always?) be a multiple of the thread execution width,
			//	but I don't have a documented proof of ,
			//	so let's not rely on that assumption.
			
			itsFloodFillFromMaskComputePipelineState = try itsDevice.makeComputePipelineState(
				function: theGPUFloodFillFromMaskComputeFunction)
		} catch {
			assertionFailure("Couldn't create itsFloodFillFromMaskComputePipelineState: \(error)")
			return false
		}

		
		//	As of October 2017, the threadExecutionWidth is 32 on all iOS hardware.
		//	If this ever changes, I'll need to review my code and perhaps make some changes.
		//
		//		Note:  The threadExecutionWidth is a hardware constant that depends
		//		only on the given MTLDevice, so it doesn't matter which of our pipeline states
		//		we use to check it.
		//
		//	If some future GPU provides a threadExecutionWidth > 32
		//	KaleidoPaint will still run correctly.  But it will be
		//	needlessly inefficient, because it'll be ignoring
		//	the newly available thread capacity.
		//
		assert(
			itsFloodFillSetUpQueueComputePipelineState.threadExecutionWidth == KP_THREAD_EXECUTION_WIDTH,
			"threadExecutionWidth != KP_THREAD_EXECUTION_WIDTH (32).  Review all code that uses KP_THREAD_EXECUTION_WIDTH"
		)
		
		
		//	Composition

		//	For each of its<N>LayerCompositionComputePipelineStates,
		//	the thread group size is likely to be a multiple of the thread execution width,
		//	but I don't have a documented proof of that, so let's
		//	not rely on that assumption.

		do {
			itsOneLayerCompositionComputePipelineState = try itsDevice.makeComputePipelineState(
				function: theGPU1LayerCompositionComputeFunction)
		} catch {
			assertionFailure("Couldn't create itsOneLayerCompositionComputePipelineState: \(error)")
			return false
		}

		do {
			itsTwoLayerCompositionComputePipelineState = try itsDevice.makeComputePipelineState(
				function: theGPU2LayerCompositionComputeFunction)
		} catch {
			assertionFailure("Couldn't create itsTwoLayerCompositionComputePipelineState: \(error)")
			return false
		}

		do {
			itsThreeLayerCompositionComputePipelineState = try itsDevice.makeComputePipelineState(
				function: theGPU3LayerCompositionComputeFunction)
		} catch {
			assertionFailure("Couldn't create itsThreeLayerCompositionComputePipelineState: \(error)")
			return false
		}
		
		return true
	}
	
	func setUpFixedBuffers() -> Bool {
	
		//	itsFloodFillQueueBuffer provides scratch space
		//	for KPFloodFillSetUpQueueComputeFunction() and
		//	KPFloodFillProcessQueueComputeFunction()
		//	to keep queues (one queue per thread) of pixel locations
		//	that still need to generate runs of theFillColorDisplayP3Linear.
		//
		//	In practice the number of such pixel locations is relatively small,
		//	typically at most 1 or 2 pixels per row.
		//	Nevertheless we want to allocate a buffer
		//	that's big enough even for the worst-case scenario.
		//
		//	With 4-way flood fill:
		//		A pixel gets put onto the queue by the pixel immediately
		//		above or below it in the unit cell (allowing for wraparound),
		//		so we know that each pixel may get added at most twice,
		//		hence twice the number of pixels would be a safe buffer length.
		//		But note that in any given row, at most every other pixel
		//		can put a neighboring pixel in the row above it (resp. below it)
		//		onto the queue, because otherwise adjacent pixels would form runs
		//		in their respective rows and get processed together.
		//		Therefore just one times the number of pixels is also
		//		a provably safe buffer length.
		//
		//	With 8-way flood fill:
		//		The worst-case scenario would seem to be a checkboard pattern,
		//		in which a given pixel may get added four times (from the SW, NW, NE and SE),
		//		but only every other pixel gets added in this way,
		//		so overall twice the number of pixels should be safe.
		//		(Confession:  I haven't thought through the details
		//		of a rigorous proof here.)
		//
		itsFloodFillQueueBuffer = itsDevice.makeBuffer(
			length:	  ( itsEightWayFloodFillFlag ? 2 : 1 )
					* itsUnitCellSize
					* itsUnitCellSize
					* MemoryLayout<FloodFillPixelCoords>.stride,
			options: MTLResourceOptions.storageModePrivate)
		if itsFloodFillQueueBuffer == nil {
			return false
		}
		
		//	itsFloodFillInterCallBuffer provides scratch space
		//	for KPFloodFillSetUpQueueComputeFunction() and
		//	KPFloodFillProcessQueueComputeFunction() to keep track
		//	of progress from one compute-function call to the next.
		//
		itsFloodFillInterCallBuffer = itsDevice.makeBuffer(
			length: MemoryLayout<FloodFillInterCallData>.stride,
			options: MTLResourceOptions.storageModePrivate)
		if itsFloodFillInterCallBuffer == nil {
			return false
		}

		//	As we compute each flood fill, we'll store its runs
		//	in itsSingleFillScratchBuffer, organized by rows.
		//	Each row gets assigned enough space for (itsUnitCellSize / 2)
		//	instances of the RLERunInImplicitRow structure,
		//	which is the most runs a single row can contain
		//	(because any two consecutive runs need at least
		//	one differently-colored pixel in between to separate them).
		//	There are itsUnitCellSize rows, so the total buffer size is
		//	itsUnitCellSize * (itsUnitCellSize / 2) * MemoryLayout<RLERunInImplicitRow>.stride.
		//
		//		Design note:
		//
		//		On the one hand, if we used a raw bitmap for a scratch buffer,
		//		we'd need only
		//
		//			itsUnitCellSize * itsUnitCellSize * MemoryLayout<Byte>.stride
		//
		//		bytes, which is half as much memory as we're using
		//		for this RLE-based buffer.
		//
		//		On the other hand, the RLE-based buffer requires
		//		vastly fewer buffer-writes at fill-generation time
		//		(just a few, as opposed to every pixel with the bitmap-based buffer).
		//		Then afterwards, the bitmap-based approach would require
		//		reading back the whole buffer -- twice, in fact --
		//		to re-generate the forgotten runs.
		//		By contract, the RLE-based approach is not only faster
		//		but also more natural:  given that our flood-fill algorithm
		//		generates the fill as a set of runs, it makes sense to keep
		//		them as runs throughout.
		//

		itsSingleFillScratchBuffer = itsDevice.makeBuffer(
			length:	  itsUnitCellSize
					* (itsUnitCellSize / 2)
					* MemoryLayout<RLERunInImplicitRow>.stride,
			options: MTLResourceOptions.storageModePrivate)
		if itsSingleFillScratchBuffer == nil {
			return false
		}

		itsSingleFillScratchBufferRunCountsScratchBuffer = itsDevice.makeBuffer(
			length:   itsUnitCellSize
					* MemoryLayout<UInt16>.stride,
			options: MTLResourceOptions.storageModePrivate)
		if itsSingleFillScratchBufferRunCountsScratchBuffer == nil {
			return false
		}

		//	When we first compute a drawing's flood fills
		//	we don't know how much space to allow for each RLE description.
		//	The typical memory demand is very small (perhaps a few kilobytes)
		//	but the worst-case memory demand is huge (for a 1024 × 1024 image
		//	it would be (1024 * 1024 / 2) * MemoryLayout<RLERun>.stride = 3 megabytes).
		//	Allocating a worst-case-size buffer for every filled region
		//	in a complex drawing could exhaust all available memory,
		//	and iOS would terminate the app with no explanation to the user.
		//
		//	To keep total memory usage under control, while allowing
		//	for a mix of a few complex regions along with many simple ones,
		//	when the GPU first computes the flood fills it will store all the RLE's
		//	for the whole drawing in one large scratch buffer.
		//	Then, once the CPU knows how much space the RLE description
		//	for each filled region required, it will allocate a dedicated buffer
		//	of exactly the right size and ask the GPU to copy the RLE description
		//	from the scratch buffer into the dedicated buffer.
		//	The scratch buffer will then be available for re-use.
		//
		//	How big should the scratch buffer be?
		//	On average, the number of runs in one filled region
		//	will be comparable to itsUnitCellSize, so if we allow for, say,
		//	a thousand filled regions each with itsUnitCellSize RLERuns,
		//	we should be fine in almost all cases.
		//	That comes out to ~6 MB -- the size of only 6 Medium Resolution fills
		//	in the old version of KaleidoPaint -- so we can safely increase
		//	the size of this scratch buffer if we ever need to.
		//
		itsWholeDrawingScratchBuffer = itsDevice.makeBuffer(
			length:	  Int(itsWholeDrawingScratchBufferLength)
					* MemoryLayout<RLERun>.stride,
			options: MTLResourceOptions.storageModePrivate)
		if itsWholeDrawingScratchBuffer == nil {
			return false
		}
		
		//	Each successive call to record a flood fill's runs
		//	will need to know where on itsWholeDrawingScratchBuffer
		//	it should start writing data.
		//
		itsWholeDrawingScratchBufferWriteIndexBuffer = itsDevice.makeBuffer(
			length:  MemoryLayout<UInt32>.stride,
			options: MTLResourceOptions.storageModePrivate)
		if itsWholeDrawingScratchBufferWriteIndexBuffer == nil {
			return false
		}

		//	Where in itsWholeDrawingScratchBuffer should the data
		//	from each row of itsSingleFillScratchBuffer get copied?
		//
		itsRowWriteIndexScratchBuffer = itsDevice.makeBuffer(
			length:   itsUnitCellSize
					* MemoryLayout<UInt32>.stride,
			options: MTLResourceOptions.storageModePrivate)
		if itsRowWriteIndexScratchBuffer == nil {
			return false
		}
		
		//	Keep a buffer containing KP_THREAD_EXECUTION_WIDTH instances of empty RLERuns,
		//	to use as a source buffer when filling the extra space that's required
		//	to pad out the number of runs in each flood-filled region's run-length encoding
		//	to a multiple of the thread execution width.

		itsRLEPaddingBuffer = itsDevice.makeBuffer(	//	initialized to all zeros; see below
			length:   Int(KP_THREAD_EXECUTION_WIDTH)
					* MemoryLayout<RLERun>.stride,
			options: MTLResourceOptions.storageModePrivate)
		if itsRLEPaddingBuffer == nil {
			return false
		}
		
		//	makeBuffer(length:,options:) provides a zero-filled buffer,
		//	so there's no need for further initialization.
		//
		//	But if we ever needed to initialize itsRLEPaddingBuffer
		//	to non-zero default values, we could use code like this
		//
		//		let theEmptyRuns = itsRLEPaddingBuffer.contents().bindMemory(
		//			to: RLERun.self, capacity: Int(KP_THREAD_EXECUTION_WIDTH))
		//		for i in 0 ..< Int(KP_THREAD_EXECUTION_WIDTH) {
		//			theEmptyRuns[i].itsRow		= 0
		//			theEmptyRuns[i].itsStartCol	= 0
		//			theEmptyRuns[i].itsLength	= 0
		//		}
		//
		//	Note:  For that code to work, we'd need to change
		//	itsRLEPaddingBuffer's MTLResourceOptions
		//	from storageModePrivate to storageModeShared.
		//	Or, alternatively, leave it as storageModePrivate
		//	and blit to it from some other buffer
		//	that has storageModeShared.

		itsRLEPaddingBuffer.label = "array of zero-length RLERuns"
		
		return true
	}
	
	func setUpInflightBufferPools() -> Bool {

		//	Let itsUnitCellSymmetriesBufferPool start with a small buffer size,
		//	and then increase it as necessary at render time.
		//
		//		Note: A TorusGroup can have up to 12 elements,
		//		each with 4 × 4 = 16 shifts, for a total
		//		of 12 * 16 = 192 symmetries. Each UnitCellSymmetryData
		//		instance occupies 44 bytes, so that's
		//
		//			192 symmetries × 44 bytes/symmetry = 8448 bytes.
		//
		//		That's far too much data for setVertexBytes,
		//		which is why we use a GeometryGamesBufferPool instead.

		let theOriginalInstanceCount = 1

		itsUnitCellSymmetriesBufferPool = GeometryGamesBufferPool(
			device: itsDevice,
			initialBufferSize: theOriginalInstanceCount * MemoryLayout<UnitCellSymmetryData>.stride,
			storageMode: .storageModeShared,
			bufferLabel: "unit cell symmetries buffer")
		
		return true
	}
	
	func setUpTextures() -> Bool {

		itsUnitCellBaseDrawingTexture = newUnitCellTexture(
			pixelFormat: itsIntermediatePixelFormat,
			textureType: .forRenderAndFloodFill)
		if itsUnitCellBaseDrawingTexture == nil {
			assertionFailure("Failed to create itsUnitCellBaseDrawingTexture")
			return false
		}

		itsUnitCellCurveInProgressTexture = newUnitCellTexture(
			pixelFormat: itsIntermediatePixelFormat,
			textureType: .forRender)
		if itsUnitCellCurveInProgressTexture == nil {
			assertionFailure("Failed to create itsUnitCellCurveInProgressTexture")
			return false
		}

		itsUnitCellSingularitiesTexture = newUnitCellTexture(
			pixelFormat: itsIntermediatePixelFormat,
			textureType: .forRender)
		if itsUnitCellSingularitiesTexture == nil {
			assertionFailure("Failed to create itsUnitCellSingularitiesTexture")
			return false
		}

		itsUnitCellComposedTexture = newUnitCellTexture(
			pixelFormat: itsComposedPixelFormat,
			textureType: .forSampling)
		if itsUnitCellComposedTexture == nil {
			assertionFailure("Failed to create itsUnitCellComposedTexture")
			return false
		}

		return true
	}
	
	func newUnitCellTexture(
		pixelFormat: MTLPixelFormat,
		textureType: UnitCellTextureType
	) -> MTLTexture? {
		
		//	Note:
		//		We do *not* use multisampling, because the flood-fill algorithm
		//		will require regions of solid color with clean boundaries.
		
		let theBuffer: MTLBuffer?
		let theTexture: MTLTexture?
		
		switch textureType {
			
		case .forRender, .forRenderAndFloodFill:
			
			//	Set up a MTLTextureDescriptor for a non-mipmapped texture.
			let theTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
				pixelFormat: pixelFormat,
				width: itsUnitCellSize,
				height: itsUnitCellSize,
				mipmapped: false)
			theTextureDescriptor.textureType = MTLTextureType.type2D
			theTextureDescriptor.usage = [
				MTLTextureUsage.renderTarget,
				MTLTextureUsage.shaderRead]
					//	MTLTextureUsage.shaderRead is for compositing
					//	into the final composed unit cell texture.
					//
					//	Note:  We'll do the flood fills, if required for this buffer,
					//	via the MTLBuffer (see below), so there's no need
					//	to include MTLTextureUsage.shaderWrite here.
			theTextureDescriptor.storageMode = MTLStorageMode.private
			
			//	Create the texture, with access as a MTLBuffer if needed for eventual flood fills.
			if textureType == .forRenderAndFloodFill {

				//	The following code relies on theNumBytesPerPixel == 4.
				let theNumBytesPerPixel = 4

				precondition(
						pixelFormat == MTLPixelFormat.bgra8Unorm_srgb
					 || pixelFormat == MTLPixelFormat.bgra8Unorm
					 || pixelFormat == MTLPixelFormat.rgba8Unorm_srgb
					 || pixelFormat == MTLPixelFormat.rgba8Unorm,
					"Incorrect pixel format for intermediate texture")
				
				//	We'll create two "wrapper objects" for the same underlying buffer:
				//	one wrapper will be a MTLBuffer while the other will be a MTLTexture.
				//	At render time,
				//
				//		our MTLRenderCommandEncoder will access the buffer as a MTLTexture
				//			to render the triangle strips for the dots and lines
				//	but
				//		our MTLComputeCommandEncoder will access the same underlying buffer
				//			as a MTLBuffer instead, to render the flood fills.
				//
				//	The motivation for this scheme is that our KPFloodFillProcessQueueComputeFunction()
				//	needs simultaneous read and write access to the base unit cell buffer,
				//	which is possible with a MTLBuffer but not with a MTLTexture.

				//	First create a MTLBuffer of the desired size.
				theBuffer = itsDevice.makeBuffer(
					length: itsUnitCellSize * itsUnitCellSize * theNumBytesPerPixel,
					options: MTLResourceOptions.storageModePrivate)
				
				//	Then create a MTLTexture using the same underlying buffer.
				//
				//		Note:  If theBuffer is nil, then theTexture will also be nil.
				//
				theTexture = theBuffer?.makeTexture(
					descriptor: theTextureDescriptor,
					offset: 0,
					bytesPerRow: itsUnitCellSize * theNumBytesPerPixel)
			}
			else {	//	textureType == .forRender
			
				//	Create the texture as a plain MTLTexture object,
				//	with no alternative access as a buffer.
				//	(This might conceivably allow the driver to make more optimizations,
				//	but I don't really know one way or the other.)
				
				theBuffer = nil
				theTexture = itsDevice.makeTexture(descriptor: theTextureDescriptor)
			}
			
			break
			
		case .forSampling:
			
			//	Create a texture that cannot be used as a render target
			//	and cannot be accessed as a MTLBuffer, but which includes mipmap levels.
			
			theBuffer = nil

			let theTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
				pixelFormat: pixelFormat,
				width: itsUnitCellSize,
				height: itsUnitCellSize,
				mipmapped: true)
			theTextureDescriptor.textureType = MTLTextureType.type2D
			theTextureDescriptor.usage = [
				MTLTextureUsage.shaderWrite,	//	for compositing from the base drawing, 							//		curve-in-progress and singularities
				MTLTextureUsage.shaderRead]		//	for tiling the view
			theTextureDescriptor.storageMode = MTLStorageMode.private
			theTexture = itsDevice.makeTexture(descriptor: theTextureDescriptor)
			
			break
		}
		
		return theTexture
	}
	
	func setUpSamplerStates() -> Bool {
		
		itsSamplerState = makeSamplerState(mode: .repeat, anisotropic: true)
		if itsSamplerState == nil {
			assertionFailure("Couldn't create itsSamplerState")
			return false
		}
		
		return true
	}


	// MARK: -
	// MARK: rendering

	//	GeometryGamesRenderer (our superclass) provides the functions
	//
	//		render()
	//			for standard onscreen rendering
	//
	//		createOffscreenImage()
	//			for CopyImage and SaveImage
	//
	//	Those two functions handle the app-independent parts
	//	of rendering an image, but for the app-dependent parts
	//	they call encodeCommands(), which we override here
	//	to provide the app-specific content.

	override func encodeCommands(
		modelData: KaleidoPaintDocument,
		commandBuffer: MTLCommandBuffer,
		renderPassDescriptor: MTLRenderPassDescriptor,
		frameWidth: Int,
		frameHeight: Int,
		transparentBackground: Bool,
		extraRenderFlag: Bool?,
		quality: GeometryGamesImageQuality
	) {

		let wantsControlHandles = (
			modelData.itsTouchMode == .edit
		 &&	quality != .export	//	Suppress control handles when exporting image.
		)
		
		//	If any of the unit cell textures need to be redrawn,
		//	redraw them and then re-composite the composed unit cell texture.
		//
		//		Note:  The unit cell texture updates will create and use
		//		their own MTLRenderPassDescriptors.  They don't need
		//		the standard renderPassDescriptor that the caller has passed.
		//
		refreshUnitCellTexturesAsNeeded(
			modelData: modelData,
			commandBuffer: commandBuffer,
			wantsControlHandles: wantsControlHandles,
			transparentBackground: transparentBackground)

		//	Render a single rectangle, covering the whole view,
		//	using itsUnitCellComposedTexture as the texture.

		var thePageRectangle = preparePageCornersData(
								modelData: modelData,
								frameWidth: frameWidth,
								frameHeight: frameHeight)
										
		if let theRenderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
					
			theRenderEncoder.label = "final view"

			theRenderEncoder.setRenderPipelineState(itsPageRectangleRenderPipelineState)
			theRenderEncoder.setCullMode(.none)			//	the default
			theRenderEncoder.setFrontFacing(.clockwise)	//	the default
			theRenderEncoder.setVertexBytes(
								&thePageRectangle,
								length:
									KaleidoPaintRenderer.numPageCorners
								  * MemoryLayout<PageCornerVertexData>.stride,
								index: BufferIndexVFVertexAttributes)
			theRenderEncoder.setFragmentTexture(
								itsUnitCellComposedTexture,
								index:TextureIndexFFPrimary)
			theRenderEncoder.setFragmentSamplerState(
								itsSamplerState,
								index:SamplerIndexFFPrimary)
			theRenderEncoder.drawPrimitives(
								type: .triangleStrip,
								vertexStart: 0,
								vertexCount: KaleidoPaintRenderer.numPageCorners,
								instanceCount: 1)

			//	all done!
			theRenderEncoder.endEncoding()
		}
	}

	
	// MARK: -
	// MARK: unit cell refresh

	func refreshUnitCellTexturesAsNeeded(
		modelData: KaleidoPaintDocument,
		commandBuffer: MTLCommandBuffer,
		wantsControlHandles: Bool,
		transparentBackground: Bool
	) {
		//	Design note #1
		//
		//	Updating a unit cell texture may be a very slow process
		//	for complex drawings, so (in contrast to the uniform buffers
		//	that get updated every frame) we update a unit cell texture
		//	only upon demand.
		
		//	Design note #2
		//
		//	Even though we're triple-buffering the main frame buffer,
		//	there's no need to keep three copies the unit cell textures.
		//	Because
		//
		//		- the CPU never touches the unit cell textures, and
		//		- the GPU processes work stictly in the order in which it's received,
		//
		//	it's OK for frame n+1 to reuse the same buffer that frame n used.
		//	The essential point here is that the unit cell textures get created
		//	with MTLStorageModePrivate, so only the GPU may access them, never the CPU.
		//	The CPU merely queues up requests for the GPU.

		//	Design note #3
		//
		//	I had originally hoped to update the unit cell textures
		//	in the background, while the app continued to use the previous
		//	unit cell textures to redraw the view.  The hope was that the user could,
		//	for example, continue to scroll and zoom while the unit cell textures
		//	got redrawn.  Alas that plan didn't work, because MTLCommandBuffers,
		//	even when submitted to different MTLCommandQueues, never run in parallel.
		//	(At least that's the case in August 2017 on iOS 10.3.  Maybe some
		//	future version of Metal will allow parallel execution.)
		
		let theBaseDrawingNeedsFullRedraw
			= itsBaseDrawingTextureFullRedrawCount  != modelData.itsBaseDrawingTextureFullRedrawRequestCount
		let theBaseDrawingNeedsLastElement
			= itsBaseDrawingTextureLastElementCount != modelData.itsBaseDrawingTextureLastElementRequestCount
		let theCurveInProgressNeedsRedraw
			= itsCurveInProgressTextureRedrawCount  != modelData.itsCurveInProgressTextureRedrawRequestCount
		let theSingularitiesNeedRedraw
			= itsSingularitiesTextureRedrawCount    != modelData.itsSingularitiesTextureRedrawRequestCount
		let theCompositeTextureNeedsRedraw
			= itsCompositeTextureRedrawCount        != modelData.itsCompositeTextureRedrawRequestCount
		   || transparentBackground	//	To render the drawing with a transparent background,
									//		we'll need refresh itsUnitCellComposedTexture
									//		to remove the current background color.

		//	We're about to redraw the textures as requested,
		//	so let's update our counts to match the modelData's values.
		//
		itsBaseDrawingTextureFullRedrawCount  = modelData.itsBaseDrawingTextureFullRedrawRequestCount
		itsBaseDrawingTextureLastElementCount = modelData.itsBaseDrawingTextureLastElementRequestCount
		itsCurveInProgressTextureRedrawCount  = modelData.itsCurveInProgressTextureRedrawRequestCount
		itsSingularitiesTextureRedrawCount    = modelData.itsSingularitiesTextureRedrawRequestCount
		itsCompositeTextureRedrawCount        = modelData.itsCompositeTextureRedrawRequestCount

		//	If we just rendered the composite texture with a transparent background
		//	for export, we must increment the modelData's redraw request count
		//	so that the next time we render the on-screen image we'll know to refresh
		//	itsUnitCellComposedTexture to include the current background color.
		//
		if transparentBackground {
			modelData.itsCompositeTextureRedrawRequestCount += 1
		}

		//	If nothing needs a redraw, we're done.
		if !(  theBaseDrawingNeedsFullRedraw
			|| theBaseDrawingNeedsLastElement
			|| theCurveInProgressNeedsRedraw
			|| theSingularitiesNeedRedraw
			|| theCompositeTextureNeedsRedraw )
		{
			return
		}		

		//	Compute the unit cell symmetries.
		//
		//		Design note:  The unit cell symmetries typically
		//		don't change from frame to frame.  But they're easy
		//		to compute and re-computing them every frame
		//		keeps program logic and buffer management simpler.
		//
		let (theUnitCellSymmetriesBuffer, theSymmetryCount) = writeUnitCellSymmetries(
			unitCellSymmetriesBufferPool: itsUnitCellSymmetriesBufferPool,
			commandBuffer: commandBuffer,
			wallpaperGroup: modelData.itsWallpaperGroup)

		//	Allocate a scratch buffer large enough to hold all required triangle strips.
		let theTriStripScratchBufferVertexCount
			= max(Dot.triStripBufferVertexCount, Curve.triStripBufferVertexCount)
		let theTriStripScratchBuffer
			= UnsafeMutablePointer<SIMD2<Float32>>.allocate(
				capacity: theTriStripScratchBufferVertexCount)
		defer {
			theTriStripScratchBuffer.deallocate()
		}
								
		//	Does the host support non-uniform threadgroup sizes?
		//
		//		Non-uniform threadgroup sizes are available
		//		in MTLGPUFamilyApple4 and higher, meaning
		//		an A11 SoC or newer. Every iPhone that runs
		//		iOS 17 or higher has an A12 SoC or newer,
		//		so no problem there. However several iPad models
		//		run iPadOS 17 (one even runs iPadOS 18) but
		//		has only an A10 or A10x SoC. So until we start
		//		requiring iOS 26 or later, we'll need to keep
		//		checking whether non-uniform thread groups sizes
		//		are available or not.
		//
		let theNonuniformThreadGroupSizesAreAvailable = itsDevice.supportsFamily(.apple4)

		
		if theBaseDrawingNeedsFullRedraw
		|| theBaseDrawingNeedsLastElement {

			if theBaseDrawingNeedsFullRedraw {
			
				//	In the typical case where the drawing is non-empty and
				//	at least one triangle strip precedes the first flood fill,
				//	it would be slightly more efficient to clear the texture
				//	as part of the first render pass in the loop below.
				//	But we clear it here instead, in a separate render pass,
				//	to keep the code logic simple.
				clearTexture(itsUnitCellBaseDrawingTexture, commandBuffer: commandBuffer)
			}

			//	Prepare theRenderPassDescriptor for triangle strips
			//	with MTLLoadActionLoad, not MTLLoadActionClear.
			let theRenderPassDescriptor = MTLRenderPassDescriptor()
			guard let theColorAttachmentDescriptor = theRenderPassDescriptor.colorAttachments[0] else {
				preconditionFailure("Failed to find unit cell color attachment for base-drawing render pass")
			}
			theColorAttachmentDescriptor.texture = itsUnitCellBaseDrawingTexture
			theColorAttachmentDescriptor.loadAction = MTLLoadAction.load
			theColorAttachmentDescriptor.storeAction = MTLStoreAction.store

			//	If the GPU needs to create masks for any new flood fills,
			//	it should write the RLERuns into itsWholeDrawingScratchBuffer
			//	beginning at index 0.
			guard let theBlitEncoder = commandBuffer.makeBlitCommandEncoder() else {
				assertionFailure("Failed to create theBlitEncoder to clear itsWholeDrawingScratchBufferWriteIndex")
				return
			}
			theBlitEncoder.label = "set whole drawing scratch buffer write index to zero"
			theBlitEncoder.fill(
				buffer: itsWholeDrawingScratchBufferWriteIndexBuffer,
				range: 0 ..< itsWholeDrawingScratchBufferWriteIndexBuffer.length,
				value: 0x00)
			theBlitEncoder.endEncoding()

			//	Render the unit cell's content.
			//
			//	We'll create a MTLRenderCommandEncoder at the beginning
			//	of each series of Dot and Curves, and finalize it
			//	at the beginning of each series of Fill and of course
			//	also at the end of the loop if necessary.
			//
			var theOptionalRenderEncoder: MTLRenderCommandEncoder? = nil
			
			let theElementsCount = modelData.itsElements.count
			let theStartIndex = (
				theElementsCount > 0 ?
					(theBaseDrawingNeedsFullRedraw ?
						0 :						//	render full drawing
						theElementsCount - 1	//	render last element only
					) :
					0	//	nothing to render
			)
			for i in theStartIndex ..< theElementsCount {
			
				let theElement = modelData.itsElements[i]
				
				if let theBrushstroke = theElement as? Brushstroke {
				
					//	If no MTLRenderCommandEncoder is present,
					//	create and initialize a new one now.
					if theOptionalRenderEncoder == nil {
					
						guard let theNewRenderEncoder = commandBuffer.makeRenderCommandEncoder(
								descriptor: theRenderPassDescriptor) else {
							assertionFailure("Failed to create theNewRenderEncoder for triangle-strip render pass")
							return
						}
						theNewRenderEncoder.label = "base drawing triangle strips"
						theNewRenderEncoder.setRenderPipelineState(
							modelData.itsColorBySymmetryFlag ?
								itsTriStripCBSRenderPipelineState :
								itsTriStripRenderPipelineState )
						theNewRenderEncoder.setVertexBuffer(
							theUnitCellSymmetriesBuffer,
							offset: 0,
							index: BufferIndexVFCoveringTransformations)
							
						theOptionalRenderEncoder = theNewRenderEncoder
					}
					
					guard let theRenderEncoder = theOptionalRenderEncoder else {
						preconditionFailure("Internal error:  theOptionalRenderEncoder is nil")
					}
					
					//	Render theElement.
					
					if !modelData.itsColorBySymmetryFlag {

						var theTriStripColor: SIMD4<Float16>
							= theElement.itsColor.asSIMDHalf()

						theRenderEncoder.setFragmentBytes(
							&theTriStripColor,
							length: MemoryLayout.size(ofValue: theTriStripColor),
							index: BufferIndexFFMisc)
					}

					theBrushstroke.render(
						renderEncoder: theRenderEncoder,
						metricOfDet1: modelData.itsUnitCellPlacement.itsMetricOfDet1,
						scratchBuffer: theTriStripScratchBuffer,
						symmetryCount: theSymmetryCount)
					
					//	Let theOptionalRenderEncoder remain non-nil
					//	for possible use with subsequent Dots and Curves.
				}
				
				if let theFill = theElement as? Fill {
				
					//	If a MTLRenderCommandEncoder is present,
					//	finalize it and clear our reference.
					//
					if let theRenderEncoder = theOptionalRenderEncoder {

						theRenderEncoder.endEncoding()
						theOptionalRenderEncoder = nil
					}
					
					theFill.render(
						device: itsDevice,
						commandBuffer: commandBuffer,
						unitCellSize: itsUnitCellSize,
						unitCellTexture: itsUnitCellBaseDrawingTexture,
						floodFillQueueBuffer: itsFloodFillQueueBuffer,
						floodFillInterCallBuffer: itsFloodFillInterCallBuffer,
						singleFillScratchBuffer: itsSingleFillScratchBuffer,
						singleFillScratchBufferRunCountsScratchBuffer: itsSingleFillScratchBufferRunCountsScratchBuffer,
						wholeDrawingScratchBuffer: itsWholeDrawingScratchBuffer,
						wholeDrawingScratchBufferWriteIndexBuffer: itsWholeDrawingScratchBufferWriteIndexBuffer,
						rowWriteIndexScratchBuffer: itsRowWriteIndexScratchBuffer,
						floodFillSetUpQueuePipelineState: itsFloodFillSetUpQueueComputePipelineState,
						floodFillProcessQueuePipelineState: itsFloodFillProcessQueueComputePipelineState,
						floodFillAssignScratchRowsPipelineState: itsFloodFillAssignScratchRowsComputePipelineState,
						floodFillSingleToWholePipelineState: itsFloodFillSingleToWholeComputePipelineState,
						floodFillFromMaskComputePipelineState:
							itsFloodFillFromMaskComputePipelineState,
						symmetries:
							modelData.itsWallpaperGroup.torusGroup.itsElements,
						colorBySymmetry:
							modelData.itsColorBySymmetryFlag,
						nonuniformThreadGroupSizesAreAvailable: theNonuniformThreadGroupSizesAreAvailable
					)
				}
			}
			//	If a MTLRenderCommandEncoder remains open,
			//	finalize it and clear our reference.
			//
			if let theRenderEncoder = theOptionalRenderEncoder {
			
				theRenderEncoder.endEncoding()
				theOptionalRenderEncoder = nil
			}

			//	As the user drags a dot or curve around in real time,
			//	it can slip underneath filled regions' masks.
			//	As soon as the user lifts his/her finger, we will of course
			//	recompute the filled regions and their masks,
			//	but the recomputation is too slow to do over and over
			//	while the user's finger is still down.
			//	So while the user's finger is still down, let's re-draw
			//	the selected dot or curve on top of all other drawing elements,
			//	to keep it visible.
			//
			if let theSelectedElement = modelData.itsControlHandleHit?.itsElement {
			
				if let theSelectedBrushstroke = theSelectedElement as? Brushstroke {
				
					guard let theSelectedBrushstrokeRenderEncoder
						= commandBuffer.makeRenderCommandEncoder(
							descriptor: theRenderPassDescriptor) else {
						assertionFailure("Failed to create theRenderEncoder for selected brushstroke triangle-strip render pass")
						return
					}
					theSelectedBrushstrokeRenderEncoder.label = "selected brushstroke triangle strip"
					theSelectedBrushstrokeRenderEncoder.setRenderPipelineState(
						modelData.itsColorBySymmetryFlag ?
							itsTriStripCBSRenderPipelineState :
							itsTriStripRenderPipelineState )
					theSelectedBrushstrokeRenderEncoder.setVertexBuffer(
						theUnitCellSymmetriesBuffer,
						offset: 0,
						index: BufferIndexVFCoveringTransformations)

					if !modelData.itsColorBySymmetryFlag {

						var theTriStripColor: SIMD4<Float16>
							= theSelectedBrushstroke.itsColor.asSIMDHalf()

						theSelectedBrushstrokeRenderEncoder.setFragmentBytes(
							&theTriStripColor,
							length: MemoryLayout.size(ofValue: theTriStripColor),
							index: BufferIndexFFMisc)
					}

					theSelectedBrushstroke.render(
						renderEncoder: theSelectedBrushstrokeRenderEncoder,
						metricOfDet1: modelData.itsUnitCellPlacement.itsMetricOfDet1,
						scratchBuffer: theTriStripScratchBuffer,
						symmetryCount: theSymmetryCount)

					theSelectedBrushstrokeRenderEncoder.endEncoding()
				}
			}

			if wantsControlHandles {

				//	We define each a control handle as a square, and
				//	let KPControlHandleFragmentFunction() shade it
				//	to make it round and smooth.
				
				guard let theControlHandleRenderEncoder = commandBuffer.makeRenderCommandEncoder(
						descriptor: theRenderPassDescriptor) else {
					assertionFailure("Failed to create theControlHandleRenderEncoder")
					return
				}
				theControlHandleRenderEncoder.label = "control handle triangle strips"

				theControlHandleRenderEncoder.setRenderPipelineState(itsControlHandleRenderPipelineState)
			
				//	The shape of the control handle in the square unit cell
				//	depends on the metric.  Let's set one prototype
				//	control handle, and then let the vertex shader
				//	scale and translate it according to the size of each control point.
				//
				var theProtypeControlHandleVertices: [ControlHandleVertexData]
					= prototypeControlHandleVertices(
						metricOfDet1: modelData.itsUnitCellPlacement.itsMetricOfDet1)
				theControlHandleRenderEncoder.setVertexBytes(
					&theProtypeControlHandleVertices,
					length: gControlHandleVertexCount
								* MemoryLayout<ControlHandleVertexData>.stride,
					index: BufferIndexVFVertexAttributes)

				theControlHandleRenderEncoder.setVertexBuffer(
					theUnitCellSymmetriesBuffer,
					offset: 0,
					index: BufferIndexVFCoveringTransformations)
				
				let theFillMarkerRadius = modelData.fillMarkerRadius()

				//	Even if we're drawing only the last element,
				//	we still need to draw all the control handles,
				//	just in case the last element has covered some
				//	previously drawn control handle.
				//
				for theElement in modelData.itsElements {

					let theElementIsSelected = (modelData.itsControlHandleHit?.itsElement === theElement)
				
					if let theDot = theElement as? Dot {
					
						theDot.renderControlHandle(
							isSelected: theElementIsSelected,
							renderEncoder: theControlHandleRenderEncoder,
							symmetryCount: theSymmetryCount)
					}
				 
					if let theCurve = theElement as? Curve {
					
							let theSelectedNode =
								(theElementIsSelected ? modelData.itsControlHandleHit?.itsNode : nil)
									
							theCurve.renderControlHandles(
								selectedNode: theSelectedNode,
								renderEncoder: theControlHandleRenderEncoder,
								symmetryCount: theSymmetryCount)
					}
				 
					if let theFill = theElement as? Fill {
					
						theFill.renderControlHandle(
							isSelected: theElementIsSelected,
							renderEncoder: theControlHandleRenderEncoder,
							symmetryCount: theSymmetryCount,
							markerRadius: theFillMarkerRadius)
					}
				}
				
				theControlHandleRenderEncoder.endEncoding()
			}
		}

		if theCurveInProgressNeedsRedraw {

			let theRenderPassDescriptor = MTLRenderPassDescriptor()
			guard let theColorAttachmentDescriptor = theRenderPassDescriptor.colorAttachments[0] else {
				preconditionFailure("Failed to find unit cell color attachment for curve-in-progress render pass")
			}
			theColorAttachmentDescriptor.texture = itsUnitCellCurveInProgressTexture
			theColorAttachmentDescriptor.clearColor
				= MTLClearColorMake(0.0, 0.0, 0.0, 0.0)	//	transparent (pre-multiplied alpha)
			theColorAttachmentDescriptor.loadAction = MTLLoadAction.clear
			theColorAttachmentDescriptor.storeAction = MTLStoreAction.store

			guard let theRenderEncoder = commandBuffer.makeRenderCommandEncoder(
					descriptor: theRenderPassDescriptor) else {
				assertionFailure("Failed to create theRenderEncoder for curve-in-progress render pass")
				return
			}
			theRenderEncoder.label = "curve-in-progress triangle strips"
			theRenderEncoder.setRenderPipelineState(
				modelData.itsColorBySymmetryFlag ?
					itsTriStripCBSRenderPipelineState :
					itsTriStripRenderPipelineState )
			theRenderEncoder.setVertexBuffer(
				theUnitCellSymmetriesBuffer,
				offset: 0,
				index: BufferIndexVFCoveringTransformations)

			if let theCurveInProgress = modelData.itsCurveInProgress {

				var theCurveInProgressColor: SIMD4<Float16>
					= theCurveInProgress.itsColor.asSIMDHalf()

				theRenderEncoder.setFragmentBytes(
					&theCurveInProgressColor,
					length: MemoryLayout.size(ofValue: theCurveInProgressColor),
					index: BufferIndexFFMisc)

				theCurveInProgress.render(
					renderEncoder: theRenderEncoder,
					metricOfDet1: modelData.itsUnitCellPlacement.itsMetricOfDet1,
					scratchBuffer: theTriStripScratchBuffer,
					symmetryCount: theSymmetryCount)
			}

			theRenderEncoder.endEncoding()
		}
		
		if theSingularitiesNeedRedraw {

			let theRenderPassDescriptor = MTLRenderPassDescriptor()
			guard let theColorAttachmentDescriptor = theRenderPassDescriptor.colorAttachments[0] else {
				assertionFailure("Failed to find unit cell color attachment for singularities render pass")
				return
			}
			theColorAttachmentDescriptor.texture = itsUnitCellSingularitiesTexture
			theColorAttachmentDescriptor.clearColor
				= MTLClearColorMake(0.0, 0.0, 0.0, 0.0)	//	transparent (pre-multiplied alpha)
			theColorAttachmentDescriptor.loadAction = MTLLoadAction.clear
			theColorAttachmentDescriptor.storeAction = MTLStoreAction.store

			guard let theRenderEncoder = commandBuffer.makeRenderCommandEncoder(
					descriptor: theRenderPassDescriptor) else {
				assertionFailure("Failed to create theRenderEncoder for singularities render pass")
				return
			}
			defer {
				theRenderEncoder.endEncoding()
			}
			theRenderEncoder.label = "singularities triangle strips"
			theRenderEncoder.setRenderPipelineState(itsTriStripRenderPipelineState)
			theRenderEncoder.setVertexBuffer(
				theUnitCellSymmetriesBuffer,
				offset: 0,
				index: BufferIndexVFCoveringTransformations)

			let theSingularityMarkers = singularityMarkers(
											wallpaperGroup: modelData.itsWallpaperGroup)

			for theSingularityMarker in theSingularityMarkers {

				var theMarkerColor: SIMD4<Float16>
					= theSingularityMarker.itsColor.asSIMDHalf()

				theRenderEncoder.setFragmentBytes(
					&theMarkerColor,
					length: MemoryLayout.size(ofValue: theMarkerColor),
					index: BufferIndexFFMisc)

				theSingularityMarker.render(
					renderEncoder: theRenderEncoder,
					metricOfDet1: modelData.itsUnitCellPlacement.itsMetricOfDet1,
					scratchBuffer: theTriStripScratchBuffer,
					symmetryCount: theSymmetryCount)
			}
		}

		//	Now that we've updated
		//
		//		itsUnitCellBaseDrawingTexture
		//		itsUnitCellCurveInProgressTexture
		//		itsUnitCellSingularitiesTexture
		//
		//	as necessary, we can superimposed them
		//	to refresh itsUnitCellComposedTexture.
				
		guard let theComputeEncoder = commandBuffer.makeComputeCommandEncoder() else {
			assertionFailure("refreshUnitCellTexturesAsNeeded() failed to create theComputeEncoder for texture composition")
			return
		}

		var theBackgroundColorDisplayP3LinearHalf4 = (
			transparentBackground ?
				SIMD4<Float16>(0.0, 0.0, 0.0, 0.0) :
				modelData.itsBackgroundColor.asSIMDHalf()
		)

		theComputeEncoder.setBytes(&theBackgroundColorDisplayP3LinearHalf4,
							length: MemoryLayout.size(
								ofValue: theBackgroundColorDisplayP3LinearHalf4),
							index: BufferIndexCFMiscA)
		
		theComputeEncoder.setTexture(itsUnitCellComposedTexture,
							index:TextureIndexCFDst)

		let theComputePipelineState: MTLComputePipelineState
		
		if modelData.itsCurveInProgress != nil {
		
			if modelData.itsShowSingularitiesFlag {
			
				theComputeEncoder.label = "compose base drawing, curve-in-progress and singularities"

				theComputePipelineState = itsThreeLayerCompositionComputePipelineState
				
				theComputeEncoder.setTexture(
					itsUnitCellBaseDrawingTexture,		index:TextureIndexCFSrc1)
				theComputeEncoder.setTexture(
					itsUnitCellCurveInProgressTexture,	index:TextureIndexCFSrc2)
				theComputeEncoder.setTexture(
					itsUnitCellSingularitiesTexture,	index:TextureIndexCFSrc3)
			
			} else {
			
				theComputeEncoder.label = "compose base drawing and curve-in-progress"

				theComputePipelineState = itsTwoLayerCompositionComputePipelineState
				
				theComputeEncoder.setTexture(
					itsUnitCellBaseDrawingTexture,		index:TextureIndexCFSrc1)
				theComputeEncoder.setTexture(
					itsUnitCellCurveInProgressTexture,	index:TextureIndexCFSrc2)
			
			}
		
		} else {

			if modelData.itsShowSingularitiesFlag {
			
				theComputeEncoder.label = "compose base drawing and singularities"

				theComputePipelineState = itsTwoLayerCompositionComputePipelineState

				theComputeEncoder.setTexture(
					itsUnitCellBaseDrawingTexture,		index:TextureIndexCFSrc1)
				theComputeEncoder.setTexture(
					itsUnitCellSingularitiesTexture,	index:TextureIndexCFSrc2)

			} else {
			
				theComputeEncoder.label = "compose base drawing only"

				theComputePipelineState = itsOneLayerCompositionComputePipelineState
				
				theComputeEncoder.setTexture(
					itsUnitCellBaseDrawingTexture,		index:TextureIndexCFSrc1)
			
			}

		}
		theComputeEncoder.setComputePipelineState(theComputePipelineState)

		//	Dispatch one thread per pixel.
		if theNonuniformThreadGroupSizesAreAvailable {
			
			//	Dispatch one thread per pixel, using the first strategy
			//	described in Apple's article
			//
			//		https://developer.apple.com/documentation/metal/calculating_threadgroup_and_grid_sizes
			//
			//	There's no reason theThreadgroupWidth must equal the threadExecutionWidth,
			//	but it's a convenient choice.
			//
			//	itsUnitCellSize will typically be much bigger than the threadExecutionWidth
			//	and will also be an exact multiple of it, although neither of those conditions
			//	is required.
			let theThreadgroupWidth  = theComputePipelineState.threadExecutionWidth
											//	hardware-dependent constant (typically 32)
			let theThreadgroupHeight = theComputePipelineState.maxTotalThreadsPerThreadgroup
									 / theThreadgroupWidth
											//	varies according to program resource needs
			
			theComputeEncoder.dispatchThreads(
				MTLSizeMake(itsUnitCellSize, itsUnitCellSize, 1),
				threadsPerThreadgroup: MTLSizeMake(theThreadgroupWidth, theThreadgroupHeight, 1))
		}
		else
		{
			//	Legacy method:
			//
			//	Use the second strategy described in Apple's article cited above.
			//
			//	We must ensure that no threadgroup will extend beyond the bounds of the image,
			//	so that the compute function needn't include any "defensive code"
			//	to check for out-of-bounds pixel coordinates.

			var theThreadgroupWidth = theComputePipelineState.threadExecutionWidth
				//	threadExecutionWidth is a hardware-dependent constant (typically 32).
			
			//	Make sure theThreadgroupWidth is an integer sub-multiple of the image size.
			while itsUnitCellSize % theThreadgroupWidth != 0 {
				theThreadgroupWidth -= 1
			}

			var theThreadgroupHeight = theComputePipelineState.maxTotalThreadsPerThreadgroup
									 / theThreadgroupWidth
				//	maxTotalThreadsPerThreadgroup varies according to program resource needs.
			
			//	Make sure theThreadgroupHeight is an integer sub-multiple of the image size.
			while itsUnitCellSize % theThreadgroupHeight != 0 {
				theThreadgroupHeight -= 1
			}

			theComputeEncoder.dispatchThreadgroups(
				MTLSizeMake(
					itsUnitCellSize / theThreadgroupWidth,
					itsUnitCellSize / theThreadgroupHeight,
					1),
				threadsPerThreadgroup: MTLSizeMake(
					theThreadgroupWidth,
					theThreadgroupHeight,
					1))
		}

		//	all done!
		theComputeEncoder.endEncoding()


		GenerateMipmaps(
			for: itsUnitCellComposedTexture,
			commandBuffer: commandBuffer)
	}

	func clearTexture(
		_ texture: MTLTexture,
		commandBuffer: MTLCommandBuffer
	) {
	
		let theRenderPassDescriptorClear = MTLRenderPassDescriptor()
		guard let theColorAttachmentDescriptorClear
				= theRenderPassDescriptorClear.colorAttachments[0] else {
			assertionFailure("Failed to find unit cell color attachment for 'clear unit cell' render pass")
			return
		}

		theColorAttachmentDescriptorClear.texture = texture

		//	Note:  We'll set the background color when we compose
		//	the base drawing, the curve-in-progress and the singularities
		//	to get itsUnitCellComposedTexture.
		//	So here in refreshUnitCellTexturesAsNeeded() we use
		//	a transparent background for the base drawing as well as
		//	for the curve-in-progress and singularities.
		theColorAttachmentDescriptorClear.clearColor
			= MTLClearColorMake(0.0, 0.0, 0.0, 0.0)	//	transparent (pre-multiplied alpha)

		theColorAttachmentDescriptorClear.loadAction = MTLLoadAction.clear
		theColorAttachmentDescriptorClear.storeAction = MTLStoreAction.store

		//	This dummy render pass serves solely to clear the texture.
		guard let theRenderEncoder = commandBuffer.makeRenderCommandEncoder(
									descriptor: theRenderPassDescriptorClear) else {
			assertionFailure("Failed to create theRenderEncoder for 'clear' render pass")
			return
		}
		theRenderEncoder.label = "clear unit cell"
		theRenderEncoder.endEncoding()
	}
	
	func singularityMarkers(
		wallpaperGroup: WallpaperGroup
	) -> [Curve] {
	
		let theSingularityColor = LinearDisplayP3Color(
									r: 0.125,	//	opaque 7/8 black
									g: 0.125,
									b: 0.125,
									a: 1.0)
		let theSingularityLineThickness = 0.00390625	//	in unit cell coordinates

		let θ = 1.4		//	a generic angle
		let r = 0.03125	//	radius of "gyration star"
		let theGyrationStarRay = r * SIMD2<Double>(cos(θ), sin(θ))
	
		let theTorusGroup = wallpaperGroup.torusGroup
		
		let theMirrorMarkers: [Curve] = theTorusGroup.itsMirrorSegments.map {
			(endpointA, endpointB) in
			
			let theCurve = Curve(
				color: theSingularityColor,
				thickness: theSingularityLineThickness)
				
			theCurve.itsSpline.append(SplineNode(location: endpointA, type: .corner))
			theCurve.itsSpline.append(SplineNode(location: endpointB, type: .corner))
			theCurve.itsSpline.refreshParameterization()
			
			return theCurve
		}
		
		let theGyrationPointMarkers: [Curve] = theTorusGroup.itsGyrationPoints.map {
			gyrationPoint in
			
			let theCurve = Curve(
				color: theSingularityColor,
				thickness: theSingularityLineThickness)
			
			let theStarRayTip = gyrationPoint + theGyrationStarRay
				
			theCurve.itsSpline.append(SplineNode(location: gyrationPoint, type: .corner))
			theCurve.itsSpline.append(SplineNode(location: theStarRayTip, type: .corner))
			theCurve.itsSpline.refreshParameterization()
			
			return theCurve
		}

		let theDashCount = 4
		let theDashInterval = 1.0 / Double(theDashCount)

		let theGlideReflectionMarkers: [Curve]
			= theTorusGroup.itsGlideReflectionSegments.flatMap {
				(endpointA, endpointB) -> [Curve] in
			
			let theDashes = (0 ..< theDashCount).map { i -> Curve in
			
				let s₀ = (Double(i) + 0.25) * theDashInterval
				let t₀ = 1.0 - s₀
				let theDashStart = s₀ * endpointA
								 + t₀ * endpointB
			
				let s₁ = (Double(i) + 0.75) * theDashInterval
				let t₁ = 1.0 - s₁
				let theDashEnd = s₁ * endpointA
							   + t₁ * endpointB

				let theCurve = Curve(
					color: theSingularityColor,
					thickness: theSingularityLineThickness)
					
				theCurve.itsSpline.append(SplineNode(location: theDashStart, type: .corner))
				theCurve.itsSpline.append(SplineNode(location: theDashEnd,   type: .corner))
				theCurve.itsSpline.refreshParameterization()
				
				return theCurve
			}
			
			return theDashes
		}
		
		let theSymmetryMarkers = theMirrorMarkers
							   + theGyrationPointMarkers
							   + theGlideReflectionMarkers
		
		return theSymmetryMarkers
	}
	
	func prototypeControlHandleVertices(
		metricOfDet1: simd_double2x2
	) -> [ControlHandleVertexData] {	//	returns four vertices
	
		//	Choose a pair of vectors that will
		//	be orthonormal in drawing coordinates.
		let theBasisVectorA = unitLengthVector(
								v: SIMD2<Double>(1.0, 0.0),	//	arbitrary non-zero vector
								metricOfDet1: metricOfDet1)
		let theBasisVectorB = orthogonalVector(
								to: theBasisVectorA,
								metricOfDet1: metricOfDet1)
		let theBasisVectors = simd_double2x2(
			theBasisVectorA,
			theBasisVectorB
		)
		
		let thePrototypeVertices
			= gRawControlHandleVertices.map() { rawVertex in
		
			ControlHandleVertexData(
								//	right-to-left matrix action
				pos: SIMD2<Float32>(theBasisVectors * rawVertex),
				tex: SIMD2<Float32>(rawVertex)
			)
		}

		return thePrototypeVertices
	}

	override func didCommitCommandBuffer(
		_ commandBuffer: MTLCommandBuffer,
		modelData: KaleidoPaintDocument
	) {
	
		if someRLEMasksArePending(drawingElements: modelData.itsElements) {
		
			copyPendingRLEMasks(
				afterWaitingFor: commandBuffer,
				drawingElements: modelData.itsElements)
		}
	}
	
	private func someRLEMasksArePending(
		drawingElements: [DrawingElement]	//	not actually copied, thanks to
											//	  a Swift Array's copy-on-write feature
	) -> Bool {

		for theElement in drawingElements {
		
			if let theFill = theElement as? Fill {
			
				if theFill.itsTemporaryRLERunSequenceBuffer != nil {
					return true
				}
			}
		}

		return false
	}

	private func copyPendingRLEMasks(
		afterWaitingFor committedCommandBuffer: MTLCommandBuffer,
		drawingElements: [DrawingElement]	//	not actually copied, thanks to
											//	  a Swift Array's copy-on-write feature
	) {

		//	The superclass just now commited the committedCommandBuffer,
		//	immediately before calling didCommitCommandBuffer(),
		//	which in turn called us.
		//	Wait for the GPU to finish executing the committedCommandBuffer.
		//
		//		Note:  I hesitated to write code that blocks the CPU
		//		while the GPU completes a potentially lengthy task,
		//		but doing so keeps the organization of our algorithm
		//		much cleaner and safer, because we finalize the flood-fill masks
		//		before moving on.  If we didn't wait for the GPU now,
		//		we'd need to be prepared for the possibility that
		//		the GPU was writing to the scratch buffers
		//		*while* the CPU was preparing the next frame.
		//		Things would get messy in a hurry!
		//
		committedCommandBuffer.waitUntilCompleted()
		
		//	Even if an error occurs, we'll still want to clear
		//	all temporary RLE run sequence buffers.
		defer {
			for theElement in drawingElements {
				if let theFill = theElement as? Fill {
					theFill.itsTemporaryRLERunSequenceBuffer = nil
				}
			}
		}

		guard let theFollowUpCommandBuffer = itsCommandQueue.makeCommandBuffer() else {
			assertionFailure("Failed to create theFollowUpCommandBuffer")
			return
		}
		defer {
			theFollowUpCommandBuffer.commit()
		}

		guard let theBlitEncoder = theFollowUpCommandBuffer.makeBlitCommandEncoder() else {
			assertionFailure("Failed to create theBlitEncoder")
			return
		}
		defer {
			//	Note:  Swift promises to execute the deferred blocks in reverse order,
			//	that is, the last block submitted gets executed first, and so on back.
			theBlitEncoder.endEncoding()
		}

		theBlitEncoder.label = "copy RLE data"

		for theElement in drawingElements {
		
			if let theFill = theElement as? Fill {
			
				if let theRLERunSequenceBuffer = theFill.itsTemporaryRLERunSequenceBuffer {
				
					let theRunSequence = theRLERunSequenceBuffer.contents().bindMemory(
											to: RLERunSequence.self, capacity: 1)

					//	We've allocated plenty of space for itsWholeDrawingScratchBuffer
					//	and it's unlikley any drawing will ever fill it entirely.
					//	Nevertheless, if some drawing does contain more RLERuns
					//	than itsWholeDrawingScratchBuffer can hold,
					//	KPFloodFillSingleFillToWholeDrawingComputeFunction()
					//	will silently suppress the potential overflow.
					//	But theRLERunSequenceBuffer will still contain
					//	the RLERunSequence that the GPU would have wanted to write,
					//	if there had been enough space.
					//	So we must check now whether theRunSequence
					//	falls wholly within itsWholeDrawingScratchBuffer.
					//
					if theRunSequence.pointee.itsFirstRLERun
					 + theRunSequence.pointee.itsNumRLERuns
					 > itsWholeDrawingScratchBufferLength {
					 
						//	Pretend that theElement contains no RLERuns, and
						//	let the following code supply a KP_THREAD_EXECUTION_WIDTH number
						//	of zero-length RLERuns instead.
						//
						theRunSequence.pointee.itsNumRLERuns = 0
					}

					//	When we later go to render from itsCachedRLERunsBuffer,
					//	it will be easiest if the number of threads
					//	is a multiple of the thread execution width,
					//	which as of October 2017 is 32 on all iOS hardware.
					//	So to keep the rendering code simple, lets round
					//	the buffer size up to the nearest multiple
					//	of the thread execution width, and fill in
					//	the extra space with zero-length RLERuns.
					//
					var thePadding = KP_THREAD_EXECUTION_WIDTH - (theRunSequence.pointee.itsNumRLERuns % KP_THREAD_EXECUTION_WIDTH)
					if thePadding == KP_THREAD_EXECUTION_WIDTH {
						thePadding = 0
					}
							
					//	If the user tries to fill a region using the same color
					//	that's already there ("fill color == target color"),
					//	KPFloodFillSetUpQueueComputeFunction() will return
					//	without putting any seed pixels on the queue, and
					//	nothing will get re-colored, which is exactly the result we want.
					//	If iOS let us create a MTLBuffer of length zero
					//	to hold the resulting array of zero RLERuns,
					//	then all would be well and no special adaptations would be needed.
					//	However, makeBuffer() will fail if asked to create
					//	a zero-length MTLBuffer to hold an empty set of RLERuns.
					//	As a workaround, let's provide a KP_THREAD_EXECUTION_WIDTH number
					//	of RLERuns worth of padding, to keep the buffer size positive.
					//
					if theRunSequence.pointee.itsNumRLERuns == 0 {
						thePadding = KP_THREAD_EXECUTION_WIDTH
					}
							
					//	Allocate theCachedRLERunsBuffer.  This is the step that
					//	absolutely needs to be done on the CPU.  It's the reason
					//	the GPU couldn't do the whole job at once, but instead needed us
					//	to split the job into two pieces, with this next line of code in between.
					//	It's why didCommitCommandBuffer() exists at all!
					//
					guard let theCachedRLERunsBuffer = itsDevice.makeBuffer(
						length: Int(theRunSequence.pointee.itsNumRLERuns + thePadding) * MemoryLayout<RLERun>.stride,
						options: MTLResourceOptions.storageModePrivate) else {
						
						assertionFailure("failed to allocate theCachedRLERunsBuffer")
						return
					}
					theCachedRLERunsBuffer.label = "array of RLERuns"

					if theRunSequence.pointee.itsNumRLERuns > 0 {	//	copy() complains if the size is zero
					
						theBlitEncoder.copy(
							from: itsWholeDrawingScratchBuffer,
							sourceOffset: Int(theRunSequence.pointee.itsFirstRLERun) * MemoryLayout<RLERun>.stride,
							to: theCachedRLERunsBuffer,
							destinationOffset: 0,
							size: Int(theRunSequence.pointee.itsNumRLERuns) * MemoryLayout<RLERun>.stride)
					}
							
					if thePadding > 0 {
					
						theBlitEncoder.copy(
							from: itsRLEPaddingBuffer,
							sourceOffset: 0,
							to: theCachedRLERunsBuffer,
							destinationOffset: Int(theRunSequence.pointee.itsNumRLERuns) * MemoryLayout<RLERun>.stride,
							size: Int(thePadding) * MemoryLayout<RLERun>.stride)
					}
					
					//	We're done using itsTemporaryRLERunSequenceBuffer.
					//
					theFill.itsTemporaryRLERunSequenceBuffer = nil
					
					//	We can use itsCachedRLERunsBuffer to render future frames
					//	much more quickly, as long as the user is only
					//	rotating/translating/rescaling the drawing and/or
					//	adding new DrawingElements.  But if the user later
					//	edits this Fill or any DrawingElement that sit below it,
					//	then we'll need to recompute itsCachedRLERunsBuffer.
					//
					theFill.itsCachedRLERunsBuffer = theCachedRLERunsBuffer
				}
			}
		}
	}
	
	
	// MARK: -
	// MARK: page rectangle

	static let numPageCorners = 4

	func preparePageCornersData(
		modelData: KaleidoPaintDocument,
		frameWidth: Int,
		frameHeight: Int
	) -> [PageCornerVertexData] {	//	four corners

		//	thePageCornersBuffer will be an array of four instances
		//	of PageCornerVertexData, containing, in order,
		//	the corners of the page rectangle whose viewCoords are
		//
		//		(-1, -1)
		//		(-1, +1)
		//		(+1, -1)
		//		(+1, +1)
		//

		//	Please see the extended comment on "Coordinate systems"
		//	in KaleidoPaintCoordinateSystems.swift for an explanation
		//	of the three coordinate systems in which the page rectangle's
		//	vertices sit.
		
		var thePageCorners = Array(
			repeating: PageCornerVertexData(
						viewCoords: .zero,
						drawingCoords: .zero,
						extendedUnitCellCoords: .zero),
			count: KaleidoPaintRenderer.numPageCorners)
		
		//	View coordinates (±1, ±1) define where the page sits within the view.
		thePageCorners[0].viewCoords = SIMD2<Float>(-1.0, -1.0)
		thePageCorners[1].viewCoords = SIMD2<Float>(-1.0, +1.0)
		thePageCorners[2].viewCoords = SIMD2<Float>(+1.0, -1.0)
		thePageCorners[3].viewCoords = SIMD2<Float>(+1.0, +1.0)
		
		//	Drawing coordinates (±w/2, ±h/2) define what portion
		//	of the drawing you see within the page.
		let (theDrawingWidth, theDrawingHeight)
			= convertPageSizeToDrawingCoordinates(
				Double(frameWidth), Double(frameHeight))
		
		let theDrawingCoordinates: [ SIMD2<Double> ] = [
			SIMD2<Double>(-0.5 * theDrawingWidth, -0.5 * theDrawingHeight),
			SIMD2<Double>(-0.5 * theDrawingWidth, +0.5 * theDrawingHeight),
			SIMD2<Double>(+0.5 * theDrawingWidth, -0.5 * theDrawingHeight),
			SIMD2<Double>(+0.5 * theDrawingWidth, +0.5 * theDrawingHeight)
		]
		
		//	Convert double to float before passing value to the GPU
		//	(if the GPU needed these values, which it doesn't).
		for i in 0 ..< 4 {
			thePageCorners[i].drawingCoords = SIMD2<Float>(theDrawingCoordinates[i])
		}
		
		//	Extended unit cell coordinates account for the unit cell's placement
		//	in the drawing (typically a parallelogram) and determine how
		//	the unit cell's content gets repeated across the page.

		for i in 0 ..< 4 {
		
			let theExtendedUnitCellCoordinates
				= convertDrawingCoordinatesToExtendedUnitCellCoordinates(
					theDrawingCoordinates[i],
					unitCellPlacement: modelData.itsUnitCellPlacement)

			//	Convert double to float before passing value to the GPU.
			thePageCorners[i].extendedUnitCellCoords
				= SIMD2<Float>(theExtendedUnitCellCoordinates)

			//	Coordinate flip
			//
			//	When rendering into a MTLTexture, Metal uses
			//	an (x,y) coordinate system with x and y in the range [-1, +1]
			//	and the vertical y coordinate running upwards, but
			//	when sampling from a MTLTexture, Metal uses
			//	an (s,t) coordinate system with s and t in the range [0, 1]
			//	and the vertical t coordinate running downwards.
			//
			//		Rigorously correct conclusion:
			//			Even though our unit cell coordinates
			//			have no intrinsic notion of "up" or "down",
			//			we must at least be consistent,
			//			to compensate for a MTLTexture's
			//			different treatment of x and t,
			//			here we must send t to 1 - t.
			//
			//		Naive but perhaps nevertheless helpful explanation:
			//			We normally visualize KaleidoPaint's unit cell coordinates
			//			with the vertical coordinate running upwards.
			//			Because a MTLTexture uses a downward-running t coordinate,
			//			our t corresponds to its 1 - t.
			//
			thePageCorners[i].extendedUnitCellCoords[1]
				= Float(1.0) - thePageCorners[i].extendedUnitCellCoords[1]
		}
		
		return thePageCorners
	}


	// MARK: -
	// MARK: unit cell symmetries
	
	func writeUnitCellSymmetries(
		unitCellSymmetriesBufferPool: GeometryGamesBufferPool,
		commandBuffer: MTLCommandBuffer,
		wallpaperGroup: WallpaperGroup
	) -> (MTLBuffer, Int) {
		
		let theNumUnitCellSymmetries
			= gNumShifts * wallpaperGroup.torusGroup.itsElements.count
		
		unitCellSymmetriesBufferPool.ensureSize(
			theNumUnitCellSymmetries
			* MemoryLayout<UnitCellSymmetryData>.stride)

		let theUnitCellSymmetriesBuffer = unitCellSymmetriesBufferPool.get(forUseWith: commandBuffer)
		
		let theUnitCellSymmetries = theUnitCellSymmetriesBuffer.contents().bindMemory(
			to: UnitCellSymmetryData.self, capacity: theNumUnitCellSymmetries)

		let theTorusGroup: TorusGroup = wallpaperGroup.torusGroup

		var theCount = 0
		for Δx in gMinShift ... gMaxShift {
			for Δy in gMinShift ... gMaxShift {
				for i in 0 ..< theTorusGroup.itsElements.count {

					theUnitCellSymmetries[theCount].itsSymmetry
						= convertDouble3x3toFloat3x3(theTorusGroup.itsElements[i].itsMatrix)
					theUnitCellSymmetries[theCount].itsSymmetry[2][0] += Float(Δx)
					theUnitCellSymmetries[theCount].itsSymmetry[2][1] += Float(Δy)

					theUnitCellSymmetries[theCount].itsColorBySymmetryColor
						= theTorusGroup.itsElements[i].itsColor.asSIMDHalf()

					theCount += 1
				}
			}
		}

		let theSymmetryCount = gNumShifts * theTorusGroup.itsElements.count

		precondition(theCount == theSymmetryCount)

		return (theUnitCellSymmetriesBuffer, theSymmetryCount)
	}
}
