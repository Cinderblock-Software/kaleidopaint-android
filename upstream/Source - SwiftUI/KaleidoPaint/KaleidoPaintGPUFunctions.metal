//	KaleidoPaintGPUFunctions.metal
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

#include <metal_stdlib>
using namespace metal;
#include "KaleidoPaintGPUDefinitions.h"	//	include this *after* "using namespace metal"
										//		to get the uint32_t and uint64_t definitions


//	Control handle transition radii
//
//	Allow fairly gentle transitions,
//	for better results at small pixel sizes.

#define CONTROL_HANDLE_ALPHA_TRANSITION_INNER_RADIUS	0.9h
#define CONTROL_HANDLE_ALPHA_TRANSITION_OUTER_RADIUS	1.0h
#define CONTROL_HANDLE_COLOR_TRANSITION_INNER_RADIUS	0.7h
#define CONTROL_HANDLE_COLOR_TRANSITION_OUTER_RADIUS	0.8h

#define ALPHA_INNER_RADIUS_SQ	(CONTROL_HANDLE_ALPHA_TRANSITION_INNER_RADIUS * CONTROL_HANDLE_ALPHA_TRANSITION_INNER_RADIUS)
#define ALPHA_OUTER_RADIUS_SQ	(CONTROL_HANDLE_ALPHA_TRANSITION_OUTER_RADIUS * CONTROL_HANDLE_ALPHA_TRANSITION_OUTER_RADIUS)
#define COLOR_INNER_RADIUS_SQ	(CONTROL_HANDLE_COLOR_TRANSITION_INNER_RADIUS * CONTROL_HANDLE_COLOR_TRANSITION_INNER_RADIUS)
#define COLOR_OUTER_RADIUS_SQ	(CONTROL_HANDLE_COLOR_TRANSITION_OUTER_RADIUS * CONTROL_HANDLE_COLOR_TRANSITION_OUTER_RADIUS)


//	Note:  In the Metal shading language, uint and a uint32_t are the same thing,
//	but for some reason a call like
//
//		[theGPUFunctionLibrary newFunctionWithName:@"KPFloodFillSetUpQueueComputeFunction"
//								constantValues:theCompileTimeConstants error:&theError];
//
//	insists on uint, and fails if it finds a uint32_t here.
//

constant bool	gColorBySymmetry		[[ function_constant(0) ]];	//	8-bit boolean
constant bool	gColorNormally = ! gColorBySymmetry;
constant uint	gUnitCellSize			[[ function_constant(1) ]];	//	32-bit unsigned integer (see Note above)
constant uint	gRLEScratchBufferLength	[[ function_constant(2) ]];	//	32-bit unsigned integer (see Note above)
constant bool	gEightWayFloodFillFlag	[[ function_constant(3) ]];	//	8-bit boolean
constant bool	gComposeWithFirstLayer	[[ function_constant(4) ]];	//	8-bit boolean, always true
constant bool	gComposeWithSecondLayer	[[ function_constant(5) ]];	//	8-bit boolean
constant bool	gComposeWithThirdLayer	[[ function_constant(6) ]];	//	8-bit boolean


#pragma mark -
#pragma mark Page rectangle

struct PageRectangleVertexInput
{
	float2	viewCoords				[[ attribute(VertexAttributePRViewCoords)				]],
		//	drawingCoordinates,	//	= (±w/2, ±h/2), not needed in GPU vertex function
			extendedUnitCellCoords	[[ attribute(VertexAttributePRExtendedUnitCellCoords)	]];
};

struct PageRectangleVertexOutput
{
	float4	position [[ position ]];
	float2	texCoords;
};

vertex PageRectangleVertexOutput KPPageRectangleVertexFunction(
	PageRectangleVertexInput	in	[[ stage_in  ]])
{
	PageRectangleVertexOutput	out;
	
	out.position	= float4(in.viewCoords, 0.0, 1.0);
	out.texCoords	= in.extendedUnitCellCoords;

	return out;
}

fragment half4 KPPageRectangleFragmentFunction(
	PageRectangleVertexOutput	in				[[ stage_in							]],
	texture2d<half>				texture			[[ texture(TextureIndexFFPrimary)	]],
	sampler						textureSampler	[[ sampler(SamplerIndexFFPrimary)	]])
{
	return texture.sample(textureSampler, in.texCoords);
}


#pragma mark -
#pragma mark Unit cell triangle strips

struct TriStripVertexInput
{
	float2	pos [[ attribute(VertexAttributePosition) ]];	//	in (slightly extended) unit cell coordinates
};

struct TriStripVertexOutput
{
	float4	position				[[ position															]];
	half4	colorBySymmetryColor	[[ user(colorBySymmetryColor), function_constant(gColorBySymmetry)	]];
};

struct TriStripFragmentInput
{
	half4	colorBySymmetryColor	[[ user(colorBySymmetryColor), function_constant(gColorBySymmetry)	]];
};


vertex TriStripVertexOutput KPTriStripVertexFunction(
	      TriStripVertexInput	in					[[ stage_in															]],
	const device UnitCellSymmetryData	*coveringTransformations	[[ buffer(BufferIndexVFCoveringTransformations)		]],
	      ushort		iid							[[ instance_id														]])
{
	float3					theTransformedPosition;	//	in extended unit cell coordinates
	TriStripVertexOutput	out;
	
	theTransformedPosition = coveringTransformations[iid].itsSymmetry * float3(in.pos, 1.0);
	
	//	Convert from [0,1] unit cell coordinates to [-1,+1] clipping coordinates,
	//	and append z = 0 and w = 1.
	out.position	= float4(
						-1.0 + 2.0 * theTransformedPosition.x,
						-1.0 + 2.0 * theTransformedPosition.y,
						0.0,
						1.0);

	if (gColorBySymmetry)
		out.colorBySymmetryColor = coveringTransformations[iid].itsColorBySymmetryColor;

	return out;
}

fragment half4 KPTriStripFragmentFunction(
	TriStripFragmentInput	in		[[ stage_in														]],
	constant half4			&color	[[ buffer(BufferIndexFFMisc), function_constant(gColorNormally)	]])
{
	if (gColorBySymmetry)
		return in.colorBySymmetryColor;
	else
		return color;
}


#pragma mark -
#pragma mark Unit cell control handles

struct ControlHandleVertexInput
{
	float2	pos [[ attribute(VertexAttributePosition)	]],	//	in (slightly extended) unit cell coordinates
			tex [[ attribute(VertexAttributeTexCoords)	]];	//	in [-1.0, +1.0] × [-1.0, +1.0] coordinates
};

struct ControlHandleVertexOutput
{
	float4	position	[[ position			]];
	float2	texCoords	[[ user(texCoords)	]];	//	in [-1.0, +1.0] × [-1.0, +1.0] coordinates
};

struct ControlHandleFragmentInput
{
	float2	texCoords	[[ user(texCoords)	]];	//	in [-1.0, +1.0] × [-1.0, +1.0] coordinates
};

vertex ControlHandleVertexOutput KPControlHandleVertexFunction(
	      ControlHandleVertexInput			in							[[ stage_in										]],
	const device UnitCellSymmetryData		*coveringTransformations	[[ buffer(BufferIndexVFCoveringTransformations)	]],
	      constant ControlHandlePlacement	&controlHandlePlacement		[[ buffer(BufferIndexVFMisc)					]],
	      ushort							iid							[[ instance_id									]])
{
	float2						theTranslatedPosition;
	float3						theTransformedPosition;	//	in extended unit cell coordinates
	ControlHandleVertexOutput	out;
	
	//	in.pos contains one of the four vertices of a rectangle
	//	which is typically oblique in unit cell coordinates,
	//	but which becomes a perfect square when the unit cell
	//	gets mapped to a parallelogram in drawing coordinates.
	//	The oblique rectangle is centered at the origin
	//	and has area 4 in unit cell coordinates,
	//	so a circle inscribed in it will map to a unit circle
	//	if the parallelogram has unit area.
	
	//	Scale the oblique rectangle to the desired radius,
	//	and translate it to the desired center point.
	//
	theTranslatedPosition	= controlHandlePlacement.itsCenter
							+ controlHandlePlacement.itsRadius * in.pos;

	theTransformedPosition	= coveringTransformations[iid].itsSymmetry * float3(theTranslatedPosition, 1.0);
	
	//	Convert from [0,1] unit cell coordinates to [-1,+1] clipping coordinates,
	//	and append z = 0 and w = 1.
	out.position	= float4(
						-1.0 + 2.0 * theTransformedPosition.x,
						-1.0 + 2.0 * theTransformedPosition.y,
						0.0,
						1.0);

	//	Pass the texture coordinates along for interpolation.
	out.texCoords = in.tex;

	return out;
}

fragment half4 KPControlHandleFragmentFunction(
	ControlHandleFragmentInput		in						[[ stage_in					]],
	constant ControlHandleColors	&controlHandleColors	[[ buffer(BufferIndexFFMisc)]])
{
	half	theRadiusSquared,
			theAlpha,
			s,
			t;
	half4	theColor;
	
	theRadiusSquared	= (half)in.texCoords[0] * (half)in.texCoords[0]
						+ (half)in.texCoords[1] * (half)in.texCoords[1];
	
	theAlpha			= clamp(  (ALPHA_OUTER_RADIUS_SQ - theRadiusSquared)
							/ (ALPHA_OUTER_RADIUS_SQ - ALPHA_INNER_RADIUS_SQ),
							0.0h,
							1.0h);
	
	s					= clamp(  (COLOR_OUTER_RADIUS_SQ - theRadiusSquared)
							/ (COLOR_OUTER_RADIUS_SQ - COLOR_INNER_RADIUS_SQ),
							0.0h,
							1.0h);
	t					= 1.0h - s;

	theColor			= s * controlHandleColors.itsInnerColor
						+ t * controlHandleColors.itsOuterColor;

	return theColor * theAlpha;	//	premultiplied alpha
}


#pragma mark -
#pragma mark Unit cell flood fill

//	Notes on buffer indices
//
//	Note #1
//		On the one hand, for best efficiency on Apple Silicon GPUs,
//		it makes sense for the flood fill code to store pixel coordinates as uint16_t.
//		On the other hand, when indexing pixels in aUnitCellBuffer,
//		which views the image as a single linear array of ~1 million elements,
//		those 16-bit coordinates will need to get promoted to 32-bit values.
//
//	Note #2
//		Even though the image width n would fit within a 16-bit integer,
//		we'll often declare it as a 32-bit integer instead, so that
//		products like (n * theRow) evaluate to a 32-bit value, with no overflow.
//
//	Note #3
//		Conceptually, an *unsigned* integer best represents a buffer index.
//		But according to WWDC 2016 Session #606, iOS provides faster device memory adressing
//		when the compiler knows that the offset will fit into a *signed* 32-bit int or smaller.
//		So we'll explicitly cast all 32-bit buffer indices to int32_t,
//		to let the compiler know that its fast memory addressing is OK.
//


//	Run-time limit on compute functions?
//
//		On iOS (but perhaps not on macOS?) Metal puts a pretty severe limit
//		on how long it's willing to let any single GPU compute function run
//		before it terminates the whole command buffer with an error message
//
//			Execution of the command buffer was aborted due to an error during execution.
//			Caused GPU Hang Error (IOAF code 3)
//
//		or, sometimes in an earlier version of the code, with the error
//
//			Execution of the command buffer was aborted due to an error during execution.
//			Discarded (victim of GPU error/recovery) (IOAF code 5)
//
//		To work around this, I took the original KPFloodFillComputeFunction()
//		and split it into two functions, KPFloodFillSetUpQueueComputeFunction()
//		and KPFloodFillProcessQueueComputeFunction().
//		For each flood fill, we'll call KPFloodFillSetUpQueueComputeFunction() once
//		and then call KPFloodFillProcessQueueComputeFunction() many times
//		(perhaps 16 calls for a 1024×1024 image or 64 calls for a 2048×2048 image).
//

kernel void KPFloodFillSetUpQueueComputeFunction(
	device uint32_t					*aUnitCellBuffer		[[ buffer(BufferIndexCFMiscA) ]],
	constant FloodFillRequest		*fillRequest			[[ buffer(BufferIndexCFMiscB) ]],
	device FloodFillPixelCoords		*aFloodFillQueueBuffer	[[ buffer(BufferIndexCFMiscC) ]],
	device FloodFillInterCallData	*interCallData			[[ buffer(BufferIndexCFMiscF) ]],
	ushort							aGridID	[[ thread_position_in_threadgroup ]] )	//	∈ {0, 1, … , NUM_FLOOD_FILL_THREADS - 1}

{
	uint32_t	n;	//	Use a 32-bit integer, as explained in "Notes on buffer indices" above.
	uint16_t	theCoordinateMask;
	uint32_t	theTargetColor,	//	For our purposes, a color is a 32-bit unsigned integer.
								//		See further details at the definition of itsTargetColor.
				theTotalBufferLength,		//	in FloodFillPixelCoords (not bytes)
				theBufferLengthPerThread;	//	in FloodFillPixelCoords (not bytes)
	uint16_t	i,
				theCol,
				theRow,
				theThreadIndex;

	//	For conciseness…
	n = gUnitCellSize;

	//	The unit cell size n is always a power of two,
	//	so the most efficient way to evaluate (x % n) is to use a mask.
	//	For example, for a 1024 × 1024 image ( = 0x0400 × 0x0400 in hexadecimal),
	//
	//		x % 0x0400
	//	  = x & 0x03FF
	//
	theCoordinateMask = ((uint16_t) n) - 1;

	//	itsTargetColor will be whatever color we find at itsFillPoints[0].
	theTargetColor = aUnitCellBuffer[	//	Cf. Note #3 of "Notes on buffer indices"
				( n * uint32_t(fillRequest->itsFillPoints[0][1] & theCoordinateMask)
					+ uint32_t(fillRequest->itsFillPoints[0][0] & theCoordinateMask) )];

	//	Let thread 0 save theTargetColor for use in KPFloodFillProcessQueueComputeFunction().
	if (aGridID == 0)
		interCallData->itsTargetColor = theTargetColor;

	//	The CPU will dispatch NUM_FLOOD_FILL_THREADS copies of KPFloodFillProcessQueueComputeFunction()
	//	running in parallel on separate threads, each with its own queue
	//	containing the coordinates of those pixels that have been discovered
	//	on its assigned rows but not yet processed.
	//	Pixels belonging to row r will get assigned to the thread of index
	//
	//		  r % NUM_FLOOD_FILL_THREADS
	//		= r & FLOOD_FILL_THREAD_INDEX_MASK
	//
	//	The caller has provided aFloodFillQueueBuffer for this purpose, of size
	//
	//		(gEightWayFloodFillFlag ? 2 : 1) * n * n * sizeof(FloodFillPixelCoords)
	//
	//	so each thread will have enough space for
	//
	//		(gEightWayFloodFillFlag ? 2 : 1) * n * n / NUM_FLOOD_FILL_THREADS
	//
	//	items of type FloodFillPixelCoords.
	//	Each thread will keep track of where its queue
	//	currently begins and ends within that buffer.
	//
	//		Note #1:  Unlike in my old implementation
	//		of the traditional 4-way or 8-way flood fill,
	//		here we color a pixel when it comes off of the queue,
	//		not when it goes on.
	//		This ensures that each run will get filled as a single unit,
	//		with no risk of it splitting into two parts
	//		(which would be less efficient, especially when
	//		generating a run-length encoded description directly).
	//
	//		Note #2:  The proof accompanying the allocation of itsFloodFillQueueBuffer
	//		in setUpFixedBuffers() in KaleidoPaintRenderer.swift
	//		proves that each row will require at most n items worth of buffer space
	//		in the case of 4-way flood filling.  In the case of 8-way flood filling,
	//		it conjectures that 2n items worth of buffer space per row will always suffice,
	//		but it doesn't give a rigorous proof.
	//

	theTotalBufferLength		= (gEightWayFloodFillFlag ? 2 : 1) * n * n;
	theBufferLengthPerThread	= theTotalBufferLength / NUM_FLOOD_FILL_THREADS;

	interCallData->itsQueueBeginIndex[aGridID]	= aGridID * theBufferLengthPerThread;
	interCallData->itsQueueEndIndex[aGridID]	= interCallData->itsQueueBeginIndex[aGridID];
	
	//	If the target and fill colors aren't distinct,
	//	then leave each thread's queue empty and return,
	//	so nothing gets drawn at all.
	if (theTargetColor == fillRequest->itsFillColor)
		return;

	//	aUnitCellBuffer stores the pixels in row-major order,
	//	starting at the top row and working its way down,
	//	so address aUnitCellBuffer as
	//
	//		aUnitCellBuffer[(int32_t)( n*v + h )]
	//

	//	For each fill point...
	for (i = 0; i < fillRequest->itsNumFillPoints; i++)
	{
		theCol = fillRequest->itsFillPoints[i][0] & theCoordinateMask;
		theRow = fillRequest->itsFillPoints[i][1] & theCoordinateMask;
		
		//	Make sure that the fill point has the target color,
		//	to ensure that it will get processed when it comes off the queue.
		//	Normally all fill points will already have the target color,
		//	but if the user taps near the border between two colors,
		//	it's possible that the original up-to-12 symmetrical tap point images,
		//	when converted from floating-point coordinates to integer pixel coordinates,
		//	might not all map to pixels of the same color.
		if (aGridID == 0)
		{
			aUnitCellBuffer[(int32_t)( n * theRow  +  theCol )]	//	Cf. Note #3 of "Notes on buffer indices"
				= interCallData->itsTargetColor;
		}
		
		//	Put the fill point onto aFloodFillQueue.
		theThreadIndex = theRow & FLOOD_FILL_THREAD_INDEX_MASK;
		if (aGridID == theThreadIndex)
		{
			(aFloodFillQueueBuffer + interCallData->itsQueueEndIndex[aGridID])->itsCol = theCol;
			(aFloodFillQueueBuffer + interCallData->itsQueueEndIndex[aGridID])->itsRow = theRow;
			interCallData->itsQueueEndIndex[aGridID]++;
		}
	}
	
	//	The CPU code will now call KPFloodFillProcessQueueComputeFunction()
	//	as many times as needed...
}

kernel void KPFloodFillProcessQueueComputeFunction(
	device uint32_t					*aUnitCellBuffer						[[ buffer(BufferIndexCFMiscA) ]],
	constant FloodFillRequest		*fillRequest							[[ buffer(BufferIndexCFMiscB) ]],
	device FloodFillPixelCoords		*aFloodFillQueueBuffer					[[ buffer(BufferIndexCFMiscC) ]],
	device RLERunInImplicitRow		*aSingleFillScratchBuffer				[[ buffer(BufferIndexCFMiscD) ]],
	device uint16_t					*someSingleFillScratchBufferRunCounts	[[ buffer(BufferIndexCFMiscE) ]],
	device FloodFillInterCallData	*interCallData							[[ buffer(BufferIndexCFMiscF) ]],
	ushort							aGridID	[[ thread_position_in_threadgroup ]] )	//	∈ {0, 1, … , NUM_FLOOD_FILL_THREADS - 1}

{
	uint32_t					n;	//	Use a 32-bit integer, as explained in "Notes on buffer indices" above.
	uint16_t					theCoordinateMask,
								theIncrement,
								theDecrement,
								theRowOffset[2];
	uint32_t					theTargetColor,	//	For our purposes, a color is a 32-bit unsigned integer.
								theFillColor,	//		For details, see thecomment accompanying
												//		the definition of FloodFillRequest.itsFillColor.
								theNumPixelsFilledThisTimeThroughTheLoopByThisOneThread,
								theNumPixelsFilledThisTimeThroughTheLoopByAllThreads,
								theNumPixelsFilledSoFar,
								theRowBaseIndex,
								theIndex;
	uint16_t					theCol;
	bool						theRunIsPresent;
	FloodFillPixelCoords		theBasePoint;	//	for quicker (?) access as thread-local memory
	uint16_t					theRunStart,	//	first pixel in the run
								theRunStop;		//	last pixel in the run
	device RLERunInImplicitRow	*theScratchBufferEntry;
	uint16_t					theRowOffsetIndex,
								theNbrStartCol,
								theNbrStopCol,
								theNbrRow;
	uint32_t					theNbrRowBaseIndex;
	uint16_t					theNbrGridID;
	bool						theNbrRunHasBeenSeeded;
	uint16_t					i;

	//	Warning:  Be careful when declaring threadgroup variables.
	//
	//		threadgroup uint32_t	foo,
	//								bar;
	//
	//	puts foo into threadgroup but leaves bar in regular thread-specific memory.
	//	To get the desired effect, one must instead write
	//
	//		threadgroup uint32_t	foo;
	//		threadgroup uint32_t	bar;
	//
	threadgroup uint32_t	theSumForOneThread[NUM_FLOOD_FILL_THREADS];

	//	Note on execution barriers
	//
	//	Apple's "Metal Shading Language Specification" says that
	//
	//		If simdgroup_barrier (resp. threadgroup_barrier) is
	//		inside a conditional statement and if any thread enters
	//		the conditional statement and executes the barrier,
	//		then all threads in the SIMD-group (resp. threadgroup)
	//		must enter the conditional and execute the barrier.
	//
	//	and similarly for loops.  Thus the code bracketed by
	//	"if (theRunIsPresent)" must contain no barriers.


	//	For conciseness…
	n = gUnitCellSize;

	//	See comments on theCoordinateMask in KPFloodFillSetUpQueueComputeFunction() above.
	theCoordinateMask = ((uint16_t) n) - 1;

	//	For increasing or decreasing a texture coordinate by 1.
	theIncrement	= 1;
	theDecrement	= ((uint16_t) n) - 1;	//	express "-1" as an unsigned integer, modulo n
	theRowOffset[0] = theDecrement;
	theRowOffset[1] = theIncrement;

	//	I'm not sure whether there's some performance advantage
	//	to copying itsTargetColor and itsFillColor into local variables,
	//	or whether the compiler would do something similar on its own,
	//	but just to be safe, let's explicitly make these values local.
	//
	//		Note:  KPFloodFillSetUpQueueComputeFunction() has already
	//		double-checked that theTargetColor and theFillColor are distinct.
	//
	theTargetColor	= interCallData->itsTargetColor;
	theFillColor	= fillRequest->itsFillColor;

	//	As explained in the comments on "Run-time limit on compute functions?" above,
	//	iOS will terminate any compute function that runs longer than some fixed time.
	//	The exact time limit -- and indeed the existence of the time limit --
	//	don't seem to be documented anywhere, so some guesswork is required
	//	to avoid running afoul of it.  A workable approach seems to be to make
	//	this function return after it processes
	//	at least CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL pixels,
	//	and then on the next call to this function let it continue
	//	where it left off the previous time.  The CPU will call it sufficiently many times
	//	that it's sure to fill the whole region.  In practice only the first few calls
	//	will do any real work;  the remaining calls will all find an empty queue
	//	and return without doing anything.  Alas these wasted calls would seem
	//	to be inevitable, given that the CPU decides how many calls to make
	//	while it's preparing the MTLCommandBuffer, before it could possibly
	//	know exactly how many calls would actually be needed for any given region.
	//	Fortunately in practice the effect on the total time required to fill a region
	//	seems to be negligible (at least to within the 2% or so precision with which
	//	I was reading execution times from Xcode Instruments).
	//
	theNumPixelsFilledSoFar = 0;

	do
	{
		theNumPixelsFilledThisTimeThroughTheLoopByThisOneThread = 0;

		//	Pull the first not-yet-processed base point off the beginning of the queue.
		//
		//		Messy technical detail:  It's possible (but rare)
		//		that a single run will have been seen by two different runs
		//		in an adjacent row.  So we must skip past
		//		any base points that have already been colored starting
		//		from some other base point that came off of the queue earlier.
		//
		//		Extra bonus:  By skipping forward to the first
		//		not-yet-colored base point, this makes it easier
		//		to write the code at the end of this do/while loop,
		//		because all threads' queues will be empty
		//		precisely when zero pixels get processed on a pass
		//		through the loop.
		//
		theRunIsPresent = false;
		while (( ! theRunIsPresent )
			&& (interCallData->itsQueueBeginIndex[aGridID]
			  < interCallData->itsQueueEndIndex[aGridID]))
		{
			//	Pull the first candidate base point off the beginning of the queue.
			theBasePoint = *(aFloodFillQueueBuffer + interCallData->itsQueueBeginIndex[aGridID]);
			interCallData->itsQueueBeginIndex[aGridID]++;
			
			theRowBaseIndex	= n * theBasePoint.itsRow;
			theIndex		= theRowBaseIndex + theBasePoint.itsCol;
			
			//	Accept theBasePoint only if it's color is still theTargetColor.
			//	Otherwise reject it, in which case, if this thread's queue isn't empty,
			//	the enclosing while() loop will move on to consider the next point on the queue.
			theRunIsPresent = (aUnitCellBuffer[(int32_t)theIndex] == theTargetColor);	//	Cf. Note #3 of "Notes on buffer indices"
		}

		//	If a base point was found,
		//	color in all the pixels in the run that contains it.
		if (theRunIsPresent)
		{
			//	The run contains at least theBasePoint.
			theRunStart	= theBasePoint.itsCol;
			theRunStop	= theRunStart;

			//	Assign theFillColor.
			aUnitCellBuffer[(int32_t)theIndex] = theFillColor;	//	Cf. Note #3 of "Notes on buffer indices"
			theNumPixelsFilledThisTimeThroughTheLoopByThisOneThread++;
			
			//	Extend the run to the left,
			//	for as long as we keep finding theTargetColor.
			while (true)
			{
				theRunStart = (theRunStart + theDecrement) & theCoordinateMask;

				theIndex = theRowBaseIndex + theRunStart;
				if (aUnitCellBuffer[(int32_t)theIndex] == theTargetColor)
				{
					aUnitCellBuffer[(int32_t)theIndex] = theFillColor;
					theNumPixelsFilledThisTimeThroughTheLoopByThisOneThread++;
				}
				else
				{
					//	We reached a pixel of some other color.
					//	Back up one step.
					theRunStart = (theRunStart + theIncrement) & theCoordinateMask;
					
					//	We're done going to the left.
					break;
				}
			}
			
			//	Extend the run to the right,
			//	for as long as we keep finding theTargetColor.
			while (true)
			{
				theRunStop = (theRunStop + theIncrement) & theCoordinateMask;

				theIndex = theRowBaseIndex + theRunStop;
				if (aUnitCellBuffer[(int32_t)theIndex] == theTargetColor)
				{
					aUnitCellBuffer[(int32_t)theIndex] = theFillColor;
					theNumPixelsFilledThisTimeThroughTheLoopByThisOneThread++;
				}
				else
				{
					//	We reached a pixel of some other color.
					//	Back up one step.
					theRunStop = (theRunStop + theDecrement) & theCoordinateMask;
					
					//	We're done going to the right.
					break;
				}
			}
			
			//	Record the run in aSingleFillScratchBuffer.
			theScratchBufferEntry = aSingleFillScratchBuffer
								  + (
								  		//	Advance to the portion of the buffer that's assigned to this row...
								  		theBasePoint.itsRow * (gUnitCellSize / 2)
									  +
										//	... and then within that portion, get a pointer to the first free slot.
										//	While we're at it, increment the run count
										//	(possibly as part of the same memory access,
										//	if the GPU has a fetch-and-add instruction).
								  		someSingleFillScratchBufferRunCounts[theBasePoint.itsRow]++
									);
			theScratchBufferEntry->itsStartCol	= theRunStart;
			theScratchBufferEntry->itsLength	= ((theRunStop - theRunStart) & theCoordinateMask) + 1;

			//	Decide what portion of the neighboring rows we should check.
			if (gEightWayFloodFillFlag)
			{
				//	8-way fill
				
				//	We typically want to start checking the pixels in each neighboring row
				//	one column before the start of the run in our own row, and
				//	finish checking them one column later:
				//
				//		┌───┬───┬───┬───┬───┬───┬───┬───┬───┐
				//		│   │   │   │   │   │   │   │   │   │
				//		├───┼───┼───┼───┼───┼───┼───┼───┼───┤
				//		│   │ ? │ ? │ ? │ ? │ ? │ ? │ ? │   │  one neighboring row
				//		├───┼───┼───┼───┼───┼───┼───┼───┼───┤
				//		│   │   │ * │ * │ * │ * │ * │   │   │  our row
				//		├───┼───┼───┼───┼───┼───┼───┼───┼───┤
				//		│   │ ? │ ? │ ? │ ? │ ? │ ? │ ? │   │  other neighboring row
				//		├───┼───┼───┼───┼───┼───┼───┼───┼───┤
				//		│   │   │   │   │   │   │   │   │   │
				//		└───┴───┴───┴───┴───┴───┴───┴───┴───┘
				//
				//	The only exceptions are when the run in our row
				//	fills the whole row or almost the whole row,
				//	in which case we must make sure that the range
				//	of pixels in the neighboring row doesn't overlap itself.
				//	If it did overlap itself, theNbrStopCol would coincide with,
				//	or immediately follow, theNbrStartCol, and
				//	the "while (true) {}" loop in the code further below
				//	would terminate prematurely.
				//
				switch ( (theRunStart - theRunStop) & theCoordinateMask )
				{
					case 1:
						//	The run in our own row fills the whole row.
						//	Use the same bounds for the neighboring row.
						theNbrStartCol	= theRunStart;
						theNbrStopCol	= theRunStop;
						break;
					
					case 2:
						//	The run in our own row fills the whole row except one pixel.
						//	Lengthen those bounds at one end or the other (but not both)
						//	to check the whole neighboring row.
						theNbrStartCol	= theRunStart;
						theNbrStopCol	= (theRunStop + theIncrement) & theCoordinateMask;
						break;
					
					default:
						//	The run in our own row fills at most (n - 2) pixels.
						//	Lengthen those bounds at both ends
						//	to check the appropriate portion neighboring row,
						//	as shown by the '?' symbols in the diagram above.
						theNbrStartCol	= (theRunStart + theDecrement) & theCoordinateMask;
						theNbrStopCol	= (theRunStop  + theIncrement) & theCoordinateMask;
						break;
				}
			}
			else
			{
				//	4-way fill
				
				//	Check only those pixels in each neighboring row
				//	that sit directly above or below the run in our own row:
				//
				//		┌───┬───┬───┬───┬───┬───┬───┬───┬───┐
				//		│   │   │   │   │   │   │   │   │   │
				//		├───┼───┼───┼───┼───┼───┼───┼───┼───┤
				//		│   │   │ ? │ ? │ ? │ ? │ ? │   │   │  one neighboring row
				//		├───┼───┼───┼───┼───┼───┼───┼───┼───┤
				//		│   │   │ * │ * │ * │ * │ * │   │   │  our row
				//		├───┼───┼───┼───┼───┼───┼───┼───┼───┤
				//		│   │   │ ? │ ? │ ? │ ? │ ? │   │   │  other neighboring row
				//		├───┼───┼───┼───┼───┼───┼───┼───┼───┤
				//		│   │   │   │   │   │   │   │   │   │
				//		└───┴───┴───┴───┴───┴───┴───┴───┴───┘
				//
				theNbrStartCol	= theRunStart;
				theNbrStopCol	= theRunStop;
			}
		}
		
		//	Make sure that any and all data that this thread
		//	wrote to interCallData and aUnitCellBuffer in the code above
		//	have arrived, before one of our "neighboring threads"
		//	tries to read that same data in the code below.
		//
		//		As per the "Note on execution barriers" above,
		//		we call this barrier *outside* any "if" block.
		//
		simdgroup_barrier(mem_flags::mem_device);

		//	Test for runs of theTargetColor in the rows immediately
		//	above and below this one.
		//
		//		Design note:  We'll test the whole row above this one,
		//		and then test the whole row below this one, in hopes
		//		of optimizing the GPU's memory caching.  This could be
		//		faster (and almost certainly won't be noticeably slower)
		//		than marching along testing the row above and row below
		//		in alternation as part of a single traversal.
		//		The thought here is that executing a few extra GPU instructions
		//		may be much cheaper than a cache miss.
		//
		for (theRowOffsetIndex = 0; theRowOffsetIndex < 2; theRowOffsetIndex++)
		{
			//	If a base point was found, then scan the row immediately below or above it,
			//	and put any newly discovered runs onto the queue of the neighboring row's thread.
			if (theRunIsPresent)
			{
				theNbrRow				= (theBasePoint.itsRow + theRowOffset[theRowOffsetIndex]) & theCoordinateMask;
				theNbrRowBaseIndex		= n * theNbrRow;
				theNbrGridID			= theNbrRow & FLOOD_FILL_THREAD_INDEX_MASK;
				theNbrRunHasBeenSeeded	= false;
				
				theCol = theNbrStartCol;
				while (true)
				{
					theIndex = theNbrRowBaseIndex + theCol;
					if (aUnitCellBuffer[(int32_t)theIndex] == theTargetColor)
					{
						if ( ! theNbrRunHasBeenSeeded )
						{
							//	A new run has begun in the neighboring row.
							//	Put the neighboring pixel onto the end of the neighbor's queue.
							//	Note that our thread is the only thread with permission
							//	to write to the neighbor's queue at this moment.
							(aFloodFillQueueBuffer + interCallData->itsQueueEndIndex[theNbrGridID])->itsCol = theCol;
							(aFloodFillQueueBuffer + interCallData->itsQueueEndIndex[theNbrGridID])->itsRow = theNbrRow;
							interCallData->itsQueueEndIndex[theNbrGridID]++;
							
							//	Note that this particular neighboring run
							//	has been put onto the queue.
							theNbrRunHasBeenSeeded = true;
						}
					}
					else
					{
						//	If a neighboring run was in progress, it's now finished.
						theNbrRunHasBeenSeeded = false;
					}
					
					if (theCol == theNbrStopCol)
						break;

					theCol = (theCol + theIncrement) & theCoordinateMask;
				}
			}

			//	Make sure that any and all data that the above "if" block
			//	wrote to portions of aUnitCellBuffer and aFloodFillQueueBuffer
			//	belonging to theNbrGridID have arrived, before a different thread
			//	tries to read those same data (either on the second interation
			//	of this inner for() loop or on the next iteration of the outer do/while loop).
			//
			//		As per the "Note on execution barriers" above,
			//		we call this barrier *outside* any "if" block.
			//
			simdgroup_barrier(mem_flags::mem_device);
		}

		//	Note:  I'm not sure whether it would make a difference or not,
		//	but to keep the code clean and robust, I'm intentionally
		//	avoiding ever having threads writing the same value
		//	to the same threadgroup variable at the same time, and also
		//	avoiding branching like "if (aGridID == 0) {do something once}".
		//
		theSumForOneThread[aGridID] = theNumPixelsFilledThisTimeThroughTheLoopByThisOneThread;
		theNumPixelsFilledThisTimeThroughTheLoopByAllThreads = 0;
		simdgroup_barrier(mem_flags::mem_threadgroup);
		for (i = 0; i < NUM_FLOOD_FILL_THREADS; i++)
			theNumPixelsFilledThisTimeThroughTheLoopByAllThreads += theSumForOneThread[i];

		theNumPixelsFilledSoFar += theNumPixelsFilledThisTimeThroughTheLoopByAllThreads;

	} while
	(
		theNumPixelsFilledThisTimeThroughTheLoopByAllThreads > 0	//	This can be 0 only when all threads' queues are empty.
	 &&
	 	theNumPixelsFilledSoFar < CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL	//	Are we at risk of getting timed out?
	);
}


kernel void KPFloodFillAssignWholeDrawingScratchBufferWriteIndices(
	const device uint16_t		*someSingleFillScratchBufferRunCounts		[[ buffer(BufferIndexCFMiscA) ]],	//	input
	      device uint32_t		*aRowWriteIndexScratchBuffer				[[ buffer(BufferIndexCFMiscB) ]],	//	output
	      device uint32_t		&aRunWholeDrawingScratchBufferWriteIndex	[[ buffer(BufferIndexCFMiscC) ]],	//	input and output
	      device RLERunSequence	&aRunSequence								[[ buffer(BufferIndexCFMiscD) ]])	//	output
{
	uint32_t	theWriteIndex;
	uint16_t	theRowIndex;
	
	//	We already know
	//
	//		aRunWholeDrawingScratchBufferWriteIndex
	//			which is the location in aRunWholeDrawingScratchBuffer
	//			to which this filled region will write its RLERuns
	//	and
	//		someSingleFillScratchBufferRunCounts
	//			which is an array containing the number of RLERuns
	//			that appear in each row of the image.
	//
	//	We may now combine those two to get
	//
	//		aRowWriteIndexScratchBuffer
	//			which will be an array containing the location
	//			in aRunWholeDrawingScratchBuffer to which each row of the image
	//			should write its RLERuns.
	//
	//	Note:  For now we don't worry about whether there's enough
	//	space in aRunWholeDrawingScratchBuffer or not.  We just write the indices
	//	of where the RLERuns will go if space is available,
	//	and let KPFloodFillSingleFillToWholeDrawingComputeFunction()
	//	worry about what to do if there isn't enough space.


	//	Design decision:  Let's compute this running sum in a single thread,
	//	rather than attempting some sort of fancy O(log(n)) time algorithm.
	//	Reasons:
	//
	//	- The single-threaded version should be acceptably fast.
	//
	//	- The O(n) single-threaded version could perhaps even be faster in practice
	//		than an O(log(n)) multi-threaded version, because the single-threaded version
	//		accesses each element of someSingleFillScratchBufferRunCounts only once,
	//		and access them in order, whereas the multi-threaded version
	//		would access each element several times, in a scattered order.
	//
	//	- In a multi-threaded version, all threads would need to be
	//		in a single threadgroup to support synchronization,
	//		and iOS devices currently support at most 512 threads in a threadgroup,
	//		so each thread would need to manage more than one array element,
	//		which would further complicate the code.
	//
	//	So let's do this computation the simple easy way, in one thread!


	//	Compute the index to which each row will write its RLERuns
	//	in KPFloodFillSingleFillToWholeDrawingComputeFunction().
	theWriteIndex = aRunWholeDrawingScratchBufferWriteIndex;
	for (theRowIndex = 0; theRowIndex < gUnitCellSize; theRowIndex++)
	{
		aRowWriteIndexScratchBuffer[theRowIndex]	= theWriteIndex;
		theWriteIndex								+= someSingleFillScratchBufferRunCounts[theRowIndex];
	}
	
	//	Record what total portion of aRunWholeDrawingScratchBuffer we'll
	//	be using in KPFloodFillSingleFillToWholeDrawingComputeFunction(),
	//	so that the data may later be copied from the scratch buffer
	//	to a dedicated buffer of exactly the right size.
	aRunSequence.itsFirstRLERun	= aRunWholeDrawingScratchBufferWriteIndex;
	aRunSequence.itsNumRLERuns	= theWriteIndex - aRunWholeDrawingScratchBufferWriteIndex;
	
	//	Update aRunWholeDrawingScratchBufferWriteIndex so that the next flood fill, if any,
	//	will know where to write its data.
	aRunWholeDrawingScratchBufferWriteIndex = theWriteIndex;
}

kernel void KPFloodFillSingleFillToWholeDrawingComputeFunction(
	const device RLERunInImplicitRow	*aSingleFillScratchBuffer				[[ buffer(BufferIndexCFMiscA) ]],	//	gUnitCellSize rows, each with space for gUnitCellSize/2 elements
	const device uint16_t				*someSingleFillScratchBufferRunCounts	[[ buffer(BufferIndexCFMiscB) ]],	//	input
	      device RLERun					*aWholeDrawingScratchBuffer				[[ buffer(BufferIndexCFMiscC) ]],
	const device uint32_t				*aRowWriteIndexScratchBuffer			[[ buffer(BufferIndexCFMiscD) ]],
	      ushort						aGridID									[[ thread_position_in_grid ]] )	//	row index in aSingleFillScratchBuffer
{
	uint16_t			theRow,
						theNumRuns,
						i;
	uint32_t			theReadIndex;
	RLERunInImplicitRow	theSrcRun;
	RLERun				theDstRun;
	uint32_t			theWriteIndex;

	//	Copy the runs from aSingleFillScratchBuffer
	//	(where they're stored sparsely, as RLERunInImplicitRow's)
	//	to itsWholeDrawingScratchBuffer (where they're packed tightly, as RLERuns).
	
	theRow		= aGridID;	//	for clarity
	theNumRuns	= someSingleFillScratchBufferRunCounts[theRow];

	for (i = 0; i < theNumRuns; i++)
	{
		//	Note:  theNumRuns will often be 0 or 1, so I intentionally
		//	didn't pre-compute buffer addresses outside the for() loop.
		
		theReadIndex	= theRow * (gUnitCellSize / 2)  +  i;
		theSrcRun		= aSingleFillScratchBuffer[(int32_t)theReadIndex];	//	Cf. Note #3 of "Notes on buffer indices"
		
		theDstRun.itsRow		= theRow;
		theDstRun.itsStartCol	= theSrcRun.itsStartCol;
		theDstRun.itsLength		= theSrcRun.itsLength;
		
		theWriteIndex = aRowWriteIndexScratchBuffer[theRow] + i;

		if (theWriteIndex < gRLEScratchBufferLength)	//	Avoid any risk of a buffer overrun.
			aWholeDrawingScratchBuffer[(int32_t)theWriteIndex] = theDstRun;	//	Cf. Note #3 of "Notes on buffer indices"
	}
}

kernel void KPFloodFillFromMaskComputeFunction(
	      device uint32_t	*aUnitCellBuffer	[[ buffer(BufferIndexCFMiscA) ]],
	      constant uint32_t	&aFillColor			[[ buffer(BufferIndexCFMiscB) ]],
	const device RLERun		*aRunBuffer			[[ buffer(BufferIndexCFMiscC) ]],
	      ushort			aGridID				[[ thread_position_in_grid ]] )	//	each thread renders one RLERun
{
	uint16_t	theCoordinateMask,
				theCol,
				theRow,
				theRunLength,
				i;
	uint32_t	theRowStart;

	//	The unit cell size n is always a power of two,
	//	so the most efficient way to evaluate (x % n) is to use a mask.
	//	For example, for a 1024 × 1024 image ( = 0x0400 × 0x0400 in hexadecimal),
	//
	//		x % 0x0400
	//	  = x & 0x03FF
	//
	theCoordinateMask = ((uint16_t) gUnitCellSize) - 1;

	theRow			= aRunBuffer[aGridID].itsRow;
	theCol			= aRunBuffer[aGridID].itsStartCol;
	theRunLength	= aRunBuffer[aGridID].itsLength;
	theRowStart		= theRow * gUnitCellSize;
	
	for (i = 0; i < theRunLength; i++)
	{
		aUnitCellBuffer[ (int32_t) (theRowStart + theCol) ] = aFillColor;	//	Cf. Note #3 of "Notes on buffer indices"
		
		theCol = (theCol + 1) & theCoordinateMask;	//	allow for runs that "wrap around" the torus unit cell
	}
}


#pragma mark -
#pragma mark Unit cell layer composition

kernel void KPLayerCompositionComputeFunction(
	texture2d<half, access::write>	aDstTexture			[[ texture(TextureIndexCFDst)												]],
	texture2d<half, access::read>	aSrcTexture1		[[ texture(TextureIndexCFSrc1), function_constant(gComposeWithFirstLayer)	]],
	texture2d<half, access::read>	aSrcTexture2		[[ texture(TextureIndexCFSrc2), function_constant(gComposeWithSecondLayer)	]],
	texture2d<half, access::read>	aSrcTexture3		[[ texture(TextureIndexCFSrc3), function_constant(gComposeWithThirdLayer)	]],
	constant half4					&aBackgroundColor	[[ buffer(BufferIndexCFMiscA)												]],
	ushort2							aGridID				[[ thread_position_in_grid ]] )
{
	half4	theComposedColor,	//	Display P3
			theSrcColor1,		//	Display P3
			theSrcColor2,		//	Display P3
			theSrcColor3,		//	Display P3
			theXRsRGBColor;		//	Extended Range sRGB

	//	Matrix adapted from gP3toSRGB in GeometryGamesColor.swift,
	//	which shows how it was computed.
	const float3x3	P3toSRGB =
					{
						//	Yes, I know, most of this "precision" is lost at half3x3 or float3x3.
						//	But there's no harm in keeping it here for future reference.
						//
						{ 1.2249401762805587, -0.0420569547096881, -0.0196375545903344},
						{-0.2249401762805597,  1.0420569547096874, -0.0786360455506319},
						{ 0.0000000000000001,  0.0000000000000000,  1.0982736001409661}
					};

	//	Blend aSrcTexture onto aDstTexture.
	//
	//		Design note:
	//
	//		The current version of KaleidoPaint (and indeed all versions so far)
	//		use fully opaque colors, so to blend one texture onto another,
	//		we may simply overwrite texture n with texture n+1
	//		whenever texture n+1's alpha value is non-zero.
	//
	//		If in the future we ever needed to blend partially transparent textures,
	//		we'd use the formula
	//
	//			dstColor = srcColor + (1.0 - srcColor.a)*dstColor
	//
	//		as explained in the comment titled "Notes on alpha blending"
	//		in GeometryGamesRenderer.swift
	//
	
	//	Start fetching the source texture values immediately.
	if (gComposeWithFirstLayer)
		theSrcColor1 = aSrcTexture1.read(aGridID);
	if (gComposeWithSecondLayer)
		theSrcColor2 = aSrcTexture2.read(aGridID);
	if (gComposeWithThirdLayer)
		theSrcColor3 = aSrcTexture3.read(aGridID);
	
	theComposedColor = aBackgroundColor;
	
	if (gComposeWithFirstLayer)
	{
		if (theSrcColor1.a != 0.0h)	//	α non-zero ⇒ pixel is fully opaque, in this version of KaleidoPaint
			theComposedColor = theSrcColor1;
	}
	if (gComposeWithSecondLayer)
	{
		if (theSrcColor2.a != 0.0h)	//	α non-zero ⇒ pixel is fully opaque, in this version of KaleidoPaint
			theComposedColor = theSrcColor2;
	}
	if (gComposeWithThirdLayer)
	{
		if (theSrcColor3.a != 0.0h)	//	α non-zero ⇒ pixel is fully opaque, in this version of KaleidoPaint
			theComposedColor = theSrcColor3;
	}

	//	Convert from linear Display P3 to linear Extended Range sRGB
	theXRsRGBColor = half4(half3(P3toSRGB * float3(theComposedColor.rgb)), theComposedColor.a);

	aDstTexture.write(theXRsRGBColor, aGridID);
}
