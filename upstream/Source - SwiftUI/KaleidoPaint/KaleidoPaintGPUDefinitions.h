//	KaleidoPaintGPUDefinitions.h
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

#ifndef KaleidoPaintGPUDefinitions_h
#define KaleidoPaintGPUDefinitions_h

#include <simd/simd.h>


//	For PageRectangleVertexInput ("PR")
enum
{
	VertexAttributePRViewCoords				= 0,
	VertexAttributePRExtendedUnitCellCoords	= 1
};

//	For TriStripVertexInput and ControlHandleVertexInput
enum
{
	VertexAttributePosition		= 0,
	VertexAttributeTexCoords	= 1
};


//	Buffer indices for vertex functions ("VF")
enum
{
	BufferIndexVFVertexAttributes			= 0,
	BufferIndexVFCoveringTransformations	= 1,
	BufferIndexVFMisc						= 2
};

//	Buffer indices for fragment functions ("FF")
enum
{
	BufferIndexFFMisc	= 0
};

//	Buffer indices for compute functions ("CF")
enum
{
	BufferIndexCFMiscA	= 0,
	BufferIndexCFMiscB	= 1,
	BufferIndexCFMiscC	= 2,
	BufferIndexCFMiscD	= 3,
	BufferIndexCFMiscE	= 4,
	BufferIndexCFMiscF	= 5
};


//	Texture and sampler indices for fragment functions ("FF")
enum
{
	TextureIndexFFPrimary	= 0
};
enum
{
	SamplerIndexFFPrimary	= 0
};

//	Texture indices for compute functions ("CF")
enum
{
	TextureIndexCFDst	= 0,
	TextureIndexCFSrc1	= 1,
	TextureIndexCFSrc2	= 2,
	TextureIndexCFSrc3	= 3
};


//	unit cell symmetries
//
//		Note #1.  If the torus group has n elements, we'll need
//		to apply (gNumShifts * n) symmetries.
//
//		Note #2.  Each color-by-symmetry color gets
//		repeated gNumShifts times, but that's OK.
//		It keeps the code simple.  A perhaps trivially more efficient --
//		but also somewhat more complicated -- approach would be
//		to keep (gNumShifts * n) symmetries in one buffer
//		and (n) colors in another buffer, and let the GPU function
//		use the instance_id to fish out the correct values.
//		But I'd rather repeat the colors and keep the code simple.
//		Among other advantages, this means we can list
//		the (gNumShifts * n) symmetries in any order.
//
typedef struct {

	simd_float3x3	itsSymmetry;
	simd_half4		itsColorBySymmetryColor;	//	used only with gColorBySymmetry
} UnitCellSymmetryData;


typedef struct
{
	simd_float2	itsCenter;	//	in unit cell coordinates
	float		itsRadius;	//	in unit cell coordinates
} ControlHandlePlacement;

typedef struct
{
	simd_half4	itsInnerColor,	//	In principle premultiplied alpha (αR,αG,αB,α)
				itsOuterColor;	//		but in practice fully opaque with α = 1 .
} ControlHandleColors;


//	MAX_FILL_POINTS is just the maximum number of elements in the torus group.
#define MAX_FILL_POINTS	12	//	The torus group for *632 has 12 elements,
							//		which is the most possible.


//	The thread execution width is 32 on all current iOS hardware
//	(as of October 2017).
//
//		Note #1:  At run time, the method setUpPipelineStates()
//		in the file KaleidoPaintRenderer.swift compares the value
//		of KP_THREAD_EXECUTION_WIDTH to a MTLComputePipelineState's
//		threadExecutionWidth and, if running in debug mode,
//		reports any disagreement.
//
//		Note #2:  If this code someday gets run on a GPU
//		with a larger thread execution width, it will still
//		work correctly (but inefficiently, given that it'll
//		be ignoring the newly available thread capacity).
//		To verify this, you can (temporarily!) change 32u to 16u
//		in the line below, and see that KaleidoPaint still runs correctly.
//
#define KP_THREAD_EXECUTION_WIDTH	32u		//	explicitly unsigned, just to be safe

//	The number of flood-fill threads should be
//
//		- a multiple of the execution width (32 = KP_THREAD_EXECUTION_WIDTH)
//
//		- a a submultiple of the various possible image widths (512, 1024, etc.)
//
//		- less than the maximum allowed number of threads per threadgroup
//			(512 on all current iOS hardware, as of August 2017)
//
//	Even though Apple's documentation makes no clear statement at all
//	about just what a "threadgroup" is, it seems that iOS schedules
//	all threads within a single threadgroup to run on the same GPU core.
//	The purpose of this is overcome latency:  while one set of 32 threads
//	is waiting for data to arrive from device memory, the GPU core may give
//	that time to a different set of 32 threads.
//
//	For the flood-fill algorithm, using 32 flood-fill threads is a good choice.
//	There's no reason to use fewer, and there's little reason to use more, either,
//	because the extra threads (corresponding to more sets of rows in the image,
//	with fewer rows per set) would mostly sit idle.  Indeed, with more threads
//	the computation would most likely run more slowly, because the various active threads
//	(those with non-empty flood fill queues) would be running in parallel
//	with inactive threads (those with empty flood fill queues) instead of in parallel
//	with each other.
//
//	A comment from WWDC 2016 Session 606 (maybe relevant here but maybe not):
//
//		"And what we find is actually that targeting your thread group
//		to fit within a single SIMD and using SIMD group barrier
//		is often faster than trying to use a larger thread group
//		in order to squeeze that additional reuse, but having
//		to use thread group barrier as a result."
//
#define NUM_FLOOD_FILL_THREADS	KP_THREAD_EXECUTION_WIDTH


//	Each row in the image will get assigned to the flood-fill thread
//	with index (theRowNumber % NUM_FLOOD_FILL_THREADS).
//	The most efficient way to compute this value is with a bitwise "and".
//	For example, if the NUM_FLOOD_FILL_THREADS is 32 (0x0020 in binary), then
//
//		  theRowNumber % 0x0020
//		= theRowNumber & 0x001F
//
#define FLOOD_FILL_THREAD_INDEX_MASK	(NUM_FLOOD_FILL_THREADS - 1)

//	As explained in the comment preceding KPFloodFillSetUpQueueComputeFunction()
//	in KaleidoPaintGPUFunctions.metal, each each flood fill gets split
//	into one call to KPFloodFillSetUpQueueComputeFunction() followed by multiple calls
//	to KPFloodFillProcessQueueComputeFunction().  The question is, how many pixels
//	can we process in each call to KPFloodFillProcessQueueComputeFunction()
//	without exceeding iOS's time limit?  I've found no official documentation
//	on the existence of this time limit, let alone its value, but empirically
//	iOS aborts the execution of a MTLComputeCommandBuffer if any individual
//	function call runs for more than about 400 milliseconds.
//
//	To evaluate the effects of various values of CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL,
//	I made a test drawing (called "serpentine") in which a single flood-filled region
//	essentially fills the whole unit cell, but because of all the vertical lines,
//	the flood-fill algorithm needs to snake up and down many time to fill it.
//	Thus, by forcing the flood fill algorithm to process a great many row
//	with only a small number of pixels per row, "serpentine" requires an unusually large
//	amount of work per pixel filled.  In other words, if the algorithm finishes
//	within the time limit for "serpentine", it's likely to finish within the time limit
//	for any region that the user is likely to create in practice.
//
//	Here's my timing data for "serpentine", on my iPad Air 2 running iOS 10.3.3.
//	Each row lists
//
//		- the value of CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL
//
//		- the number of function calls for the one region,
//			possibly including some unnecessary calls,
//			each of which finds an already-empty queue and returns
//
//		- the duration of the first (green) compute-function segment
//			in Xcode Instruments Metal System Trace dedicated
//			to this flood fill (the length of this segment might be
//			the time required to process the first function call,
//			but I'm not at all sure of that -- Instruments seems
//			to regroup and relabel the compute-function segments
//			on its own)
//
//		- the total time to draw the unit cell from scratch
//
//	Here are the results:
//
//	  	Low Resolution
//	  		0x00010000	 4 calls	 275ms ( 96ms)
//	  		0x00020000	 2 calls	 273ms (173ms)
//	  		0x00040000	 1 call		 271ms (267ms)
//	  		0x00080000	   N/A
//
//	  	Medium Resolution
//	  		0x00010000	16 calls	 967ms ( 95ms)
//	  		0x00020000	 8 calls	 967ms (169ms)
//	  		0x00040000	 4 calls	 966ms (308ms)
//	  		0x00080000	  GPU Hang Error
//
//	  	High Resolution
//	  		0x00010000	64 calls	3670ms ( 97ms)
//	  		0x00020000	32 calls	3660ms (167ms)
//	  		0x00040000	16 calls	3670ms (316ms)
//	  		0x00080000	  GPU Hang Error
//
//	In practice, it seems we could process 0x00040000 pixels per function call
//	on an iPad Air 2.  However, older Metal-compatible iOS devices will be slower.
//	For example, while the iPad Air 2's GPU runs at 450 MHz, the iPhone 5s,
//	iPad Air and iPad Mini 2 & 3 may be running at only 300 MHz.
//	So I've left a factor of 4 for safety, and set CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL
//	to only 0x00010000.  As the above timings show, making 4 times as many function calls
//	has little effect on the overall performance.  (I also tested this with the final
//	version of the app:  to draw "Mmmm.... Cookies", it takes 914ms at 0x00040000
//	and 944ms at 0x00010000, meaning a ~3% slowdown.)
//
//	2022-05-13
//		Setting
//			CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL = 0x00010000 = 65536
//		still works fine on my iPad Air 2, but sometimes fails on my iPhone SE (2020),
//		with both devices running iOS 15.4.1 (the iPhone SE has both a better processor
//		and more RAM than the iPad Air 2, which makes it all the more mysterious
//		that this problem occurs on the former but not the latter).
//		To be precise, on the iPhone SE a drawing with large flood-filled regions
//		usually renders correctly, but sometimes (in the same drawing)
//		only a horizontal band of the fill gets rendered.  When that happens,
//		the app posts the error
//
//			Execution of the command buffer was aborted due to an error
//			during execution. Internal Error (0000000e:Internal Error)
//
//		The problem persist even with
//			CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL = 0x00008000 = 32768,
//		but seems to go away with
//			CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL = 0x00004000 = 16384
//
//		The legacy version of KaleidoPaint fails in the same circumstances,
//		that is, it works fine on the old iPad Air 2 but
//		fails on the newer iPhone SE (2020), so whatever the underlying cause is,
//		it not anything that the new Swift version of KaleidoPaint has introduced.
//
#define CUTOFF_NUM_PIXELS_FILLED_PER_FLOOD_FILL_FUNCTION_CALL	0x00004000	//	= 16384


typedef struct
{
	//	For our purposes, a color is a 32-bit unsigned integer.
	//	We don't need to know the meaning of the individual bytes,
	//	although in fact it's in itsIntermediatePixelFormat,
	//	which is currently set to MTLPixelFormatBGRA8Unorm,
	//	and it stores a value in Linear Display P3.
	//	Currently α = 1 in KaleidoPaint, otherwise
	//	we'd use premultiplied alpha (αR, αG, αB, α).
	//
	uint32_t	itsFillColor;

	//	There'll typically be one fill point for each element of the torus group,
	//	but there could be fewer if the user taps sufficiently close
	//	to the torus group's singular set, because in that case several
	//	images of the tap point may fall within the same pixel.
	//
	//		Note:  KPFloodFillSetUpQueueComputeFunction() will assume that itsFillPoints
	//		are all distinct.  It's the caller's responsibility to make sure
	//		that they are.
	//
	//	Each fill point is given by its position (x,y) in unit cell pixel coordinates.
	//	The coordinates are unsigned integers.  For example, for a 1024 × 1024 image
	//	the coordinates are unsigned integers in the range [0, 1023], not floats in [0.0, 1.0].
	//
	uint16_t	itsNumFillPoints,					//	At most gMaxTorusGroupSize
				itsFillPoints[MAX_FILL_POINTS][2];	//	Positions in unit cell pixel coordinates
	
} FloodFillRequest;

//	Please see the comment preceding KPFloodFillSetUpQueueComputeFunction()
//	in KaleidoPaintGPUFunctions.metal for an explanation of why each flood fill
//	gets split into multiple compute-function calls.
//	itsQueueBeginIndex and itsQueueEndIndex keep track of the flood-fill queue's state
//	from one function call to the next.
//	If we didn't need to split each flood fill into multiple compute-function calls,
//	then these variables would be local variables within the compute function,
//	and we wouldn't need a separate buffer to store them.
//
//		Technical note:  The GPU needs to write to this FloodFillInterCallData,
//		so it must be a "real buffer", that is, we need to use setBuffer()
//		and not setBytes().  But we can use the same buffer for all the fills,
//		because the GPU takes care of the initialization.
//
typedef struct {

	uint32_t	itsTargetColor,	//	See comment accompanying FloodFillRequest.itsFillColor.
				itsQueueBeginIndex[NUM_FLOOD_FILL_THREADS],	//	integer index of first element on each thread's queue
				itsQueueEndIndex[NUM_FLOOD_FILL_THREADS];	//	integer index of element *after* last element
															//		on each thread's queue

} FloodFillInterCallData;

typedef struct
{
	uint16_t	itsCol,
				itsRow;
	
} FloodFillPixelCoords;


//	To minimize memory usage, KaleidoPaint stores flood-fill masks
//	using Run-Length Encoding (RLE).  Indeed, RLE works spectacularly
//	well with KaleidoPaint, given that each filled region has
//	a single fixed color, and typically also a very simple shape.
//
//		Design question:
//
//		A run could wrap around the torus unit cell if we wish to allow it.
//		For example, in a 1024 × 1024 unit cell, a run with
//		itsStartCol = 1020 and itsLength = 12 would span
//		pixels 1020 through 1023 and also pixels 0 through 7.
//
//		Advantages:
//			- Reduced memory usage for filled regions that wrap
//			- Conceptually natural way to represent a region on a torus
//
//		Disadvantages:
//			- Slightly more complicated GPU code for encoding
//			- Slightly more complicated GPU code for decoding
//
//		None of those advantages or disadvantages are a big deal:
//		most regions don't wrap around, so the difference in memory usage
//		will typically be small (and with RLE the memory usage may be
//		almost negligible in any case), and the performance difference
//		when encoding/decoding is also likely to be small (indeed it's
//		possible that memory access will be the bottleneck, so the little bit
//		of extra time spent in the encoding/decoding computations
//		may come "for free").
//
//		Final decision:  Allow runs to wrap around the torus,
//		because this is the conceptually natural way to do it.
//
typedef struct
{
	uint16_t	itsRow,
				itsStartCol,
				itsLength;		//	run length in pixels, along the given row
} RLERun;

//	An RLERunInImplicitRow is conceptually the same as an RLERun,
//	except that it stores only the column data.  The row is implicit.
typedef struct
{
	uint16_t	itsStartCol,
				itsLength;		//	run length in pixels, along the given row
} RLERunInImplicitRow;


typedef struct
{
	uint32_t	itsFirstRLERun,	//	index of the given sequence's first RLERun
				itsNumRLERuns;	//	number of RLERuns in the given sequence
} RLERunSequence;


#endif	//	KaleidoPaintGPUDefinitions_h
