//	KaleidoPaintFill.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import Metal


class Fill: DrawingElement {
	
	//	Fill point in [0,1] unit cell coordinates.
	//	Specifies a single point, which will get transformed
	//	under the action of the torus group.
	var itsFillPoint: SIMD2<Double>
	
	//	renderFresh() asks the GPU to temporarily store this Fill's
	//	RLE description as a part of itsWholeDrawingScratchBuffer.
	//	As soon as the commandBuffer finishes execution
	//	(for the whole drawing), we'll transfer each Fill's
	//	RLE description to a new buffer of exactly the right size,
	//	for use when rendering subsequent frames.
	//
	//	If later changes to the drawing invalidate the cached RLE,
	//	we'll set itsCachedRLERunsBuffer to nil to indicate that
	//	the Fill needs to be re-rendered.
	//
	var itsTemporaryRLERunSequenceBuffer: MTLBuffer?
	var itsCachedRLERunsBuffer: MTLBuffer?

	init(
		color: LinearDisplayP3Color
			= LinearDisplayP3Color(r: 1.0, g: 0.0, b: 1.0, a: 1.0),
		fillPoint: SIMD2<Double> = SIMD2<Double>.zero
	) {
	
		itsFillPoint = fillPoint
		
		super.init(color: color)
	}

	func render(
		device: MTLDevice,
		commandBuffer: MTLCommandBuffer,
		unitCellSize: Int,	//	length of one edge of square unit cell, typically 512, 1024 or 2048
		unitCellTexture: MTLTexture,
		floodFillQueueBuffer: MTLBuffer,
		floodFillInterCallBuffer: MTLBuffer,
		singleFillScratchBuffer: MTLBuffer,
		singleFillScratchBufferRunCountsScratchBuffer: MTLBuffer,
		wholeDrawingScratchBuffer: MTLBuffer,
		wholeDrawingScratchBufferWriteIndexBuffer: MTLBuffer,
		rowWriteIndexScratchBuffer: MTLBuffer,
		floodFillSetUpQueuePipelineState: MTLComputePipelineState,
		floodFillProcessQueuePipelineState: MTLComputePipelineState,
		floodFillAssignScratchRowsPipelineState: MTLComputePipelineState,
		floodFillSingleToWholePipelineState: MTLComputePipelineState,
		floodFillFromMaskComputePipelineState: MTLComputePipelineState,
		symmetries: [TorusGroupElement],	//	Swift Arrays use copy-on-write
		colorBySymmetry: Bool,
		nonuniformThreadGroupSizesAreAvailable: Bool
	) {
	
		guard let theUnitCellTextureBuffer = unitCellTexture.buffer else {
			assertionFailure("The unitCellTexture was apparently not created from a MTLBuffer, as our flood-fill algorithm requires.")
			return
		}
		
		//	Use a neutral fill color when dots and curves are colored by symmetry.
		//
		//		Note #1:  This code assumes itsIntermediatePixelFormat
		//		is MTLPixelFormatBGRA8Unorm.  If we someday want to use
		//		a different format, we'll need to adjust the following
		//		computation accordingly.
		//
		//		Note #2:  Apple's CPUs use a little-ending architecture,
		//		so the components of a color in MTLPixelFormatBGRA8Unorm,
		//		when written as a single UInt32, are 0xAARRGGBB .
		//
		let theStandardColor
				= UInt32(UInt8(round(itsColor.a * 255.0))) << 24
				| UInt32(UInt8(round(itsColor.r * 255.0))) << 16
				| UInt32(UInt8(round(itsColor.g * 255.0))) <<  8
				| UInt32(UInt8(round(itsColor.b * 255.0))) <<  0
		let theNeutralColor = UInt32(0xFFE0E0E0)
		let theColor: UInt32 = (colorBySymmetry ? theNeutralColor : theStandardColor)
	
		if let theCachedRLERunsBuffer = itsCachedRLERunsBuffer {
		
			//	Render the flood fill using the cached RLE description.

			renderFromRLE(
				commandBuffer: commandBuffer,
				unitCellTextureBuffer: theUnitCellTextureBuffer,
				cachedRLERunsBuffer: theCachedRLERunsBuffer,
				floodFillFromMaskComputePipelineState: floodFillFromMaskComputePipelineState,
				color: theColor,
				nonuniformThreadGroupSizesAreAvailable: nonuniformThreadGroupSizesAreAvailable
			)
		
		} else {

			//	No cached flood fill is available, so let's
			//	(re-)compute the filled region, coloring it
			//	in the unit cell for immediate use and
			//	also caching an RLE description for possible future use.
			//	That way, for example, if the user goes up and down
			//	the undo/redo stacks, we'll be able to use
			//	the cached RLE description instead of
			//	re-computing the flood fill over and over.
			
			renderFresh(
				device: device,
				commandBuffer: commandBuffer,
				unitCellSize: unitCellSize,
				unitCellTextureBuffer: theUnitCellTextureBuffer,
				floodFillQueueBuffer: floodFillQueueBuffer,
				floodFillInterCallBuffer: floodFillInterCallBuffer,
				singleFillScratchBuffer: singleFillScratchBuffer,
				singleFillScratchBufferRunCountsScratchBuffer: singleFillScratchBufferRunCountsScratchBuffer,
				wholeDrawingScratchBuffer: wholeDrawingScratchBuffer,
				wholeDrawingScratchBufferWriteIndexBuffer: wholeDrawingScratchBufferWriteIndexBuffer,
				rowWriteIndexScratchBuffer: rowWriteIndexScratchBuffer,
				floodFillSetUpQueuePipelineState: floodFillSetUpQueuePipelineState,
				floodFillProcessQueuePipelineState: floodFillProcessQueuePipelineState,
				floodFillAssignScratchRowsPipelineState: floodFillAssignScratchRowsPipelineState,
				floodFillSingleToWholePipelineState: floodFillSingleToWholePipelineState,
				symmetries: symmetries,
				color: theColor,
				nonuniformThreadGroupSizesAreAvailable: nonuniformThreadGroupSizesAreAvailable
			)
		}
	}
	
	private func renderFresh(
		device: MTLDevice,
		commandBuffer: MTLCommandBuffer,
		unitCellSize: Int,	//	length of one edge of square unit cell, typically 1024 or 2048
		unitCellTextureBuffer: MTLBuffer,
		floodFillQueueBuffer: MTLBuffer,
		floodFillInterCallBuffer: MTLBuffer,
		singleFillScratchBuffer: MTLBuffer,
		singleFillScratchBufferRunCountsScratchBuffer: MTLBuffer,
		wholeDrawingScratchBuffer: MTLBuffer,
		wholeDrawingScratchBufferWriteIndexBuffer: MTLBuffer,
		rowWriteIndexScratchBuffer: MTLBuffer,
		floodFillSetUpQueuePipelineState: MTLComputePipelineState,
		floodFillProcessQueuePipelineState: MTLComputePipelineState,
		floodFillAssignScratchRowsPipelineState: MTLComputePipelineState,
		floodFillSingleToWholePipelineState: MTLComputePipelineState,
		symmetries: [TorusGroupElement],	//	Swift Arrays use copy-on-write
		color: UInt32,	//	= 0xAARRGGBB (MTLPixelFormatBGRA8Unorm in little-ending byte order)
		nonuniformThreadGroupSizesAreAvailable: Bool
	) {

		//	Allocate a scratch buffer to hold the specifications
		// for a single flood fill.
		var theFloodFillRequest = FloodFillRequest()	//	sets default values

		theFloodFillRequest.itsFillColor = color

		//	Given that the unitCellSize is a power of two,
		//	the most efficient way to evaluate (x % unitCellSize)
		//	is to use a mask.  For example, for a 1024 × 1024 image,
		//
		//		x % unitCellSize
		//	  = x % 1024
		//	  = x % 0x0400
		//	  = x & 0x03FF
		//
		let theUnitCellCoordinateMask = Int16(unitCellSize - 1)

		let theRawFillPoint = SIMD3<Double>(itsFillPoint[0], itsFillPoint[1], 1.0)
		var theFillPoints: [SIMD2<UInt16>] = []
		theFillPoints.reserveCapacity(symmetries.count)
		for theSymmetry in symmetries {
		
			let theTransformedFillPoint
				= theSymmetry.itsMatrix * theRawFillPoint	//	right-to-left matrix action
			
			//	Translate theTransformedFillPoint to lie within the unit cell,
			//	with both coordinates in the set {0, … , unitCellSize - 1}.
			let theTranslatedFillPoint = SIMD2<UInt16>(
			
				UInt16(
					theUnitCellCoordinateMask
				  &
					Int16(floor(theTransformedFillPoint[0] * Double(unitCellSize)))
				),
				
				UInt16(
					theUnitCellCoordinateMask
				  &
					//	Metal stores the unit cell texture's rows in top-down order,
					//	in contrast to our own vertical coordinate (itsLocation[1])
					//	which runs bottom up.  So we must flip the vertical coordinate
					//	to compensate.
					//
					Int16(floor((1.0 - theTransformedFillPoint[1]) * Double(unitCellSize)))
				)
			)
				
			//	The fills points are typically distinct, but if the user taps
			//	within a texel-width of the torus group's singular set,
			//	some of the fill points may coincide.  To allow for that possibility,
			//	let's eliminate any duplicate fill points now.
			//	(Note:  In almost all cases, passing duplicate fill points
			//	to the GPU would be harmless -- the flood-fill algorithm
			//	would still run correctly -- but we could no longer guarantee
			//	that the buffer used for the flood-fill queue was big enough.)
			
			let theFillPointIsDistinct: Bool = theFillPoints.reduce(
				true,
				{ theRunningValue, thePreviousFillPoint in
					theRunningValue && (theTranslatedFillPoint != thePreviousFillPoint)
				}
			)
			
			if theFillPointIsDistinct {
			
				theFillPoints.append(theTranslatedFillPoint)
			}
		}

		//	Swift doesn't much like writing into a C-style array.
		//	To write to theFloodFillRequest.itsFillPoints,
		//	we need to access that array via an UnsafeMutablePointer.
		precondition(
			theFillPoints.count <= MAX_FILL_POINTS,
			"Internal error:  impossibly many fill points")
		theFloodFillRequest.itsNumFillPoints = UInt16(theFillPoints.count)
		withUnsafeMutableBytes(of: &theFloodFillRequest.itsFillPoints, { rawPtr in
			
			//	rawPtr is an UnsafeMutableRawBufferPointer, which
			//	.baseAddress converts to an UnsafeMutableRawPointer?, which
			//	.assumingMemoryBound(to:) converts to an UnsafeMutablePointer<UInt16>
			let theFillPointsPtr
				= rawPtr.baseAddress!.assumingMemoryBound(to: UInt16.self)
				
			for i in 0 ..< theFillPoints.count {
			
				theFillPointsPtr[2*i + 0] = theFillPoints[i][0]
				theFillPointsPtr[2*i + 1] = theFillPoints[i][1]
			}
		})


		//	Fill itsSingleFillScratchBufferRunCounts with zeros,
		//	to set every row's count to zero.
		guard let theBlitEncoder = commandBuffer.makeBlitCommandEncoder() else {
			assertionFailure("Failed to create theBlitEncoder to set scratch buffer run counts to zero")
			return
		}
		theBlitEncoder.label = "set scratch buffer run counts to zero"
		theBlitEncoder.fill(
			buffer: singleFillScratchBufferRunCountsScratchBuffer,
			range: 0 ..< singleFillScratchBufferRunCountsScratchBuffer.length,
			value: 0x00)
		theBlitEncoder.endEncoding()

		//	Compute the flood fill, coloring it in in aUnitCellTexture itself,
		//	while also recording the runs in itsSingleFillScratchBuffer.
		
		guard let theComputeEncoder = commandBuffer.makeComputeCommandEncoder() else {
			assertionFailure("Failed to create theComputeEncoder to freshly render a flood fill")
			return
		}
		defer {
			theComputeEncoder.endEncoding()
		}
		theComputeEncoder.label = "flood fill - write to scratch RLE buffer"
		
		theComputeEncoder.setBuffer(
			unitCellTextureBuffer,
			offset: 0,
			index: BufferIndexCFMiscA)

		theComputeEncoder.setBytes(
			&theFloodFillRequest,
			length: MemoryLayout.size(ofValue: theFloodFillRequest),
			index: BufferIndexCFMiscB)

		theComputeEncoder.setBuffer(
			floodFillQueueBuffer,
			offset: 0,
			index: BufferIndexCFMiscC)

		theComputeEncoder.setBuffer(
			singleFillScratchBuffer,
			offset: 0,
			index: BufferIndexCFMiscD)

		theComputeEncoder.setBuffer(
			singleFillScratchBufferRunCountsScratchBuffer,
			offset: 0,
			index: BufferIndexCFMiscE)

		theComputeEncoder.setBuffer(
			floodFillInterCallBuffer,
			offset: 0,
			index: BufferIndexCFMiscF)
			
		//	Please see the note "Run-time limit on compute functions?"
		//	in KaleidoPaintGPUFunctions.metal for an explanation of why
		//	we split each flood fill into one call to KPSetUpFloodFillQueue()
		//	followed by multiple calls to KPProcessFloodFillQueue().

		theComputeEncoder.setComputePipelineState(floodFillSetUpQueuePipelineState)
		//
		//		KPFloodFillSetUpQueueComputeFunction() expects
		//		exactly NUM_FLOOD_FILL_THREADS threads.
		//
		if nonuniformThreadGroupSizesAreAvailable {

			theComputeEncoder.dispatchThreads(
				MTLSizeMake(Int(NUM_FLOOD_FILL_THREADS), 1, 1),
				threadsPerThreadgroup: MTLSizeMake(Int(NUM_FLOOD_FILL_THREADS), 1, 1))

		} else {
		
			//	Legacy method
			theComputeEncoder.dispatchThreadgroups(
				MTLSizeMake(1, 1, 1),
				threadsPerThreadgroup: MTLSizeMake(Int(NUM_FLOOD_FILL_THREADS), 1, 1))
		}

		//	How many times must we call KPProcessFloodFillQueue() for each fill?
		//
		//		Note #1:  As long as the queue remains non-empty,
		//		each call to KPFloodFillProcessQueueComputeFunction()
		//		returns only after it colors in at least
		//		CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL pixels.
		//		So the following value of theNumProcessQueueCallsPerFloodFill
		//		guarantees that all pixels in the region will get filled,
		//		even if the region occupies the whole unit cell.
		//
		//		Note #2:  Typically all quantities are powers of two, with
		//
		//			  unitCellSize * unitCellSize
		//			> CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL
		//
		//		so the division would be exact.  Nevertheless we add in the term
		//
		//			+ (Int(CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL) - 1)
		//
		//		to "round up" in the unexpected case that the division isn't exact.
		//
		assert(unitCellSize > 0, "Internal error:  unitCellSize <= 0")
		let theNumProcessQueueCallsPerFloodFill
			=	(
					unitCellSize * unitCellSize
					 + (Int(CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL) - 1)
				)
			/ Int(CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL)

		theComputeEncoder.setComputePipelineState(floodFillProcessQueuePipelineState)
		for _ in 0 ..< theNumProcessQueueCallsPerFloodFill {

			//	KPFloodFillProcessQueueComputeFunction() expects
			//	exactly NUM_FLOOD_FILL_THREADS threads.
			//
			//		Note:  Using more than NUM_FLOOD_FILL_THREADS threads per thread group
			//		would require the compute function to use threadgroup_barrier()
			//		instead of simdgroup_barrier(), so the possible performance
			//		gain might not be so great.
			//
			if nonuniformThreadGroupSizesAreAvailable {
			
				theComputeEncoder.dispatchThreads(
					MTLSizeMake(Int(NUM_FLOOD_FILL_THREADS), 1, 1),
					threadsPerThreadgroup: MTLSizeMake(Int(NUM_FLOOD_FILL_THREADS), 1, 1))
			
			} else {
			
				//	Legacy method
				theComputeEncoder.dispatchThreadgroups(
					MTLSizeMake(1, 1, 1),
					threadsPerThreadgroup: MTLSizeMake(Int(NUM_FLOOD_FILL_THREADS), 1, 1))
			}
		}


		//	At this point the GPU will have filled the region in aUnitCellTexture
		//	and recorded the runs in itsSingleFillScratchBuffer.
		//	Now let's ask it to transfer the runs from itsSingleFillScratchBuffer
		//	(where they're stored sparsely, as RLERunInImplicitRow's)
		//	to itsWholeDrawingScratchBuffer (where they're packed tightly, as RLERuns).
		
		//	Remember what part of itsWholeDrawingScratchBuffer we're using
		//	to store this DrawingElement's RLERuns, so that later on
		//	the method copyPendingRLEMasks(afterWaitingFor:…)
		//	may transfer the RLERuns from itsWholeDrawingScratchBuffer
		//	into a set of dedicated buffers (one for each filled region)
		//	of exactly the right size.
		
		guard let theTemporaryRLERunSequenceBuffer = device.makeBuffer(
			length: MemoryLayout<RLERunSequence>.stride,
			options: MTLResourceOptions.storageModeShared)	//	CPU will need to read results
		else {
			//	This is a preconditionFailure rather than an assertionFailure
			//	because if we simply returned here, the "defer" code
			//	would call endEncoding() OK, but simply calling endEncoding()
			//	at this point would leave the app in a somewhat confused state.
			//	In any case, the above call to makeBuffer()
			//	is extremely unlikely to fail, and if it does,
			//	the app has grave problems and is unlikely to be able to continue.
			preconditionFailure("Failed to create theTemporaryRLE")
		}
		theTemporaryRLERunSequenceBuffer.label = "RLERunSequence"
		itsTemporaryRLERunSequenceBuffer = theTemporaryRLERunSequenceBuffer
		
		theComputeEncoder.setComputePipelineState(floodFillAssignScratchRowsPipelineState)
		theComputeEncoder.setBuffer(
			singleFillScratchBufferRunCountsScratchBuffer,
			offset:0,
			index:BufferIndexCFMiscA)
		theComputeEncoder.setBuffer(
			rowWriteIndexScratchBuffer,
			offset:0,
			index:BufferIndexCFMiscB)
		theComputeEncoder.setBuffer(
			wholeDrawingScratchBufferWriteIndexBuffer,
			offset:0,
			index:BufferIndexCFMiscC)
		theComputeEncoder.setBuffer(
			theTemporaryRLERunSequenceBuffer,
			offset:0,
			index:BufferIndexCFMiscD)
			
		if nonuniformThreadGroupSizesAreAvailable {
		
			theComputeEncoder.dispatchThreads(
				MTLSizeMake(1, 1, 1),	//	one thread only
				threadsPerThreadgroup: MTLSizeMake(1, 1, 1))
		
		} else {
		
			//	Legacy method
			theComputeEncoder.dispatchThreadgroups(
				MTLSizeMake(1, 1, 1),	//	one thread only
				threadsPerThreadgroup:	MTLSizeMake(1, 1, 1))
		}

		theComputeEncoder.setComputePipelineState(floodFillSingleToWholePipelineState)
		theComputeEncoder.setBuffer(
			singleFillScratchBuffer,
			offset: 0,
			index: BufferIndexCFMiscA)
		theComputeEncoder.setBuffer(
			singleFillScratchBufferRunCountsScratchBuffer,
			offset: 0,
			index: BufferIndexCFMiscB)
		theComputeEncoder.setBuffer(
			wholeDrawingScratchBuffer,
			offset: 0,
			index: BufferIndexCFMiscC)
		theComputeEncoder.setBuffer(
			rowWriteIndexScratchBuffer,
			offset: 0,
			index: BufferIndexCFMiscD)
			
		if nonuniformThreadGroupSizesAreAvailable {
		
			let theNumThreadsPerThreadgroup
				= floodFillSingleToWholePipelineState.maxTotalThreadsPerThreadgroup
				
			theComputeEncoder.dispatchThreads(
				MTLSizeMake(unitCellSize, 1, 1),	//	Each thread processes one row of the mask
				threadsPerThreadgroup: MTLSizeMake(theNumThreadsPerThreadgroup, 1, 1))
		
		} else {
		
			//	Legacy method
			//
			//	Here it's essential that the threadgroup size exactly divides the unitCellSize,
			//	which is why I'm using the hard-coded constant KP_THREAD_EXECUTION_WIDTH
			//	instead of the more flexible
			//	itsFloodFillSingleToWholePipelineState.threadExecutionWidth.
			//	As of summer 2020 both are equal to 32 on all iOS devices.
			//
			//	Each thread processes one row of the mask.
		
			precondition(
				unitCellSize % Int(KP_THREAD_EXECUTION_WIDTH) == 0,
				"KaleidoPaint's flood-fill algorithm requires that itsUnitCellSize be an integer multiple of KP_THREAD_EXECUTION_WIDTH.")

			theComputeEncoder.dispatchThreadgroups( MTLSizeMake(unitCellSize/Int(KP_THREAD_EXECUTION_WIDTH), 1, 1),
				threadsPerThreadgroup: MTLSizeMake(Int(KP_THREAD_EXECUTION_WIDTH), 1, 1))
		}
	}

	private func renderFromRLE(
		commandBuffer: MTLCommandBuffer,
		unitCellTextureBuffer: MTLBuffer,
		cachedRLERunsBuffer: MTLBuffer,
		floodFillFromMaskComputePipelineState: MTLComputePipelineState,
		color: UInt32,	//	= 0xAARRGGBB (MTLPixelFormatBGRA8Unorm in little-ending byte order)
		nonuniformThreadGroupSizesAreAvailable: Bool
	) {
		precondition(
			cachedRLERunsBuffer.label == "array of RLERuns",
			"Internal error:  expected flood-fill RLE buffer with label 'array of RLERuns'")
		
		precondition(
			cachedRLERunsBuffer.length % MemoryLayout<RLERun>.stride == 0,
			"Internal error:  invalid size for cachedRLERunsBuffer")
		let theNumRLERuns = cachedRLERunsBuffer.length / MemoryLayout<RLERun>.stride
		
		guard let theComputeEncoder = commandBuffer.makeComputeCommandEncoder() else {
			assertionFailure("Failed to create theComputeEncoder in renderFromRLE()")
			return
		}
		defer {
			theComputeEncoder.endEncoding()
		}
		theComputeEncoder.label = "flood fill - render from cachedRLERunsBuffer"

		theComputeEncoder.setComputePipelineState(floodFillFromMaskComputePipelineState)

		theComputeEncoder.setBuffer(
							unitCellTextureBuffer,
							offset: 0,
							index: BufferIndexCFMiscA)

		var theColor: UInt32 = color
		theComputeEncoder.setBytes(
							&theColor,
							length: MemoryLayout.size(ofValue: theColor),
							index: BufferIndexCFMiscB)

		theComputeEncoder.setBuffer(
							cachedRLERunsBuffer,
							offset: 0,
							index: BufferIndexCFMiscC)


		if nonuniformThreadGroupSizesAreAvailable {

			let theNumThreadsPerThreadgroup = floodFillFromMaskComputePipelineState.maxTotalThreadsPerThreadgroup
			theComputeEncoder.dispatchThreads(
					MTLSizeMake(theNumRLERuns, 1, 1),
					threadsPerThreadgroup: MTLSizeMake(theNumThreadsPerThreadgroup, 1, 1))
		}
		else
		{
			//	Legacy method

			//	The code in copyPendingRLEMasks(afterWaitingFor:drawingElements:)
			//	has rounded the size of the cachedRLERunsBuffer
			//	up to the nearest multiple of a KP_THREAD_EXECUTION_WIDTH number of RLERuns,
			//	and has filled in the extra space with harmless zero-length RLERuns.
			//	This ensures that the number of RLERuns is always a multiple
			//	of the thread execution width, which is 32 on current iOS devices.
			//
			//		When KaleidoPaint someday drops support for this legacy method,
			//		I can probably eliminate those zero-length RLERuns.
			//		Hmmm... unless threadGroupSizeIsMultipleOfThreadExecutionWidth
			//		relies on them.
			//
			precondition(
				theNumRLERuns % Int(KP_THREAD_EXECUTION_WIDTH) == 0,
				"Internal error:  this code expects theNumRLERuns to be a multiple of the KP_THREAD_EXECUTION_WIDTH")

			theComputeEncoder.dispatchThreadgroups(
				//	one thread per RLERun
				MTLSizeMake(theNumRLERuns/Int(KP_THREAD_EXECUTION_WIDTH), 1, 1),
				threadsPerThreadgroup: MTLSizeMake(Int(KP_THREAD_EXECUTION_WIDTH), 1, 1))
		}
	}
	
	
// MARK: -
// MARK: Control handle

	func renderControlHandle(
		isSelected: Bool,
		renderEncoder: MTLRenderCommandEncoder,
		symmetryCount: Int,
		markerRadius: Double
	) {
		
		var thePlacement = ControlHandlePlacement(
			itsCenter: SIMD2<Float32>(itsFillPoint),
			itsRadius: Float32(markerRadius))

		let theDarkColor = SIMD4<Float16>(0.0, 0.0, 0.0, 1.0)
		let theLightColor = SIMD4<Float16>(1.0, 1.0, 1.0, 1.0)
		var theColors = ( isSelected ?
			ControlHandleColors(	//	when node is selected
				itsInnerColor: theDarkColor,
				itsOuterColor: theLightColor) :
			ControlHandleColors(	//	when node is not selected
				itsInnerColor: theLightColor,
				itsOuterColor: theDarkColor) )

		renderEncoder.setVertexBytes(
			&thePlacement,
			length: MemoryLayout.size(ofValue: thePlacement),
			index: BufferIndexVFMisc)
			
		renderEncoder.setFragmentBytes(
			&theColors,
			length: MemoryLayout.size(ofValue: theColors),
			index: BufferIndexFFMisc)

		renderEncoder.drawPrimitives(
			type: .triangleStrip,
			vertexStart: 0,
			vertexCount: gControlHandleVertexCount,
			instanceCount: symmetryCount)
	}

	override func hitControlHandle(
		touchPointInExtendedUnitCellCoordinates: SIMD2<Double>,
		wallpaperGroup: WallpaperGroup,
		metricOfDet1: simd_double2x2,
		fillMarkerRadius: Double
	) -> ControlHandleHit?
	{
		return hitImageOfControlHandle(
			touchPointInExtendedUnitCellCoordinates: touchPointInExtendedUnitCellCoordinates,
			controlHandleCenter: itsFillPoint,
			controlHandleMeanRadius: fillMarkerRadius,
			splineNode: nil,
			wallpaperGroup: wallpaperGroup,
			metricOfDet1: metricOfDet1)
	}
}
