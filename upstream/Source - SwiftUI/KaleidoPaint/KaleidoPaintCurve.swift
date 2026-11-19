//	KaleidoPaintCurve.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import Metal


class Curve: Brushstroke {

	//	Cubic spline in [0,1] unit cell coordinates.
	//	Specifies a single curve, which will get transformed
	//	under the action of the torus group.
	var itsSpline: CubicSpline

	static let maxArcSegmentCount = 64
	static let maxArcVertexCount = 2 * (maxArcSegmentCount + 1)
	static let maxPointVertexCount = gUnitCircleVertexCount	//	might use only half-disk
	static let triStripBufferVertexCount = max(maxArcVertexCount, maxPointVertexCount)

	override init(
		color: LinearDisplayP3Color
			= LinearDisplayP3Color(r: 1.0, g: 0.0, b: 1.0, a: 1.0),
		thickness: Double = 0.01
	) {
		
		itsSpline = CubicSpline()	//	initially empty

		super.init(color: color, thickness: thickness)
	}

	override func render(
		renderEncoder: MTLRenderCommandEncoder,
		metricOfDet1: simd_double2x2,
		scratchBuffer: UnsafeMutablePointer<SIMD2<Float32>>,	//	guaranteed to be big enough
		symmetryCount: Int
	) {
	
		//	For conciseness
		let theNodes = itsSpline.itsNodes

		//	We shouldn't ever get a 0- or 1-element Curve,
		//	but if we did, the following code would
		//	simply draw nothing (and not crash!).
		assert(	//	ignored in released app
			theNodes.count >= 2,
			"Internal error:  attempting to render a curve with 0 or 1 vertex")

		//	For each node except the last one...
		for theNode in theNodes
			where !(theNode === theNodes.last) {	//	no arc begins at the last node
		
			//	...draw an arc connecting the node to the next one.
			renderArc(
				fromNode: theNode,
				renderEncoder: renderEncoder,
				metricOfDet1: metricOfDet1,
				scratchBuffer: scratchBuffer,
				symmetryCount: symmetryCount
			)
			
			//	At the first node and each corner node...
			if theNode === theNodes.first
			|| theNode.itsNodeType == .corner {

				//	...draw an initial half-dot.
				renderInitialHalfDot(
					atNode: theNode,
					renderEncoder: renderEncoder,
					metricOfDet1: metricOfDet1,
					scratchBuffer: scratchBuffer,
					symmetryCount: symmetryCount
				)
			}
		}
		
		//	Draw a final half-dot at the end.
		if theNodes.count >= 2 {
		
			renderFinalHalfDot(
				penultimateNode: theNodes[theNodes.count - 2],
				ultimateNode: theNodes[theNodes.count - 1],
				renderEncoder: renderEncoder,
				metricOfDet1: metricOfDet1,
				scratchBuffer: scratchBuffer,
				symmetryCount: symmetryCount)
		}
	}
	
	
// MARK: -
// MARK: Triangle strips

	private func renderArc(
		fromNode startNode: SplineNode,
		renderEncoder: MTLRenderCommandEncoder,
		metricOfDet1: simd_double2x2,
		scratchBuffer: UnsafeMutablePointer<SIMD2<Float32>>,	//	guaranteed to be big enough
		symmetryCount: Int
	) {
	
		//	Draw a triangle strip representing the given spline arc,
		//	using the SplineNode's parameterization
		//
		//		S(u) = ξ₀(1-u) + ξ₁u + ξ₂(1-u)³ + ξ₃u³
		//
		//	where the ξ are constants and u runs from 0 to 1.
		//
		//	Adjust the triangle strip's (varying!) thickness
		//	in unit cell coordinates to give the desired
		//	constant thickness in "unit-area parallelogram" coordinates.
	
		//	For conciseness.
		let ξ: simd_double4x2 = startNode.ξ

		//	Choose a set of u-values {u₀=0.0, u₁, u₂, … , uₙ=1.0}
		//	appropriate to the arc's bending.
		//	The u-values will typically not be evenly spaced,
		//	but instead will be denser where the arc curves more sharply,
		//	and less dense where the arc curves more gently.
		//	To find such a set of u-values, we start with a set
		//	of (maxArcSegmentCount + 1) evenly spaced candidate u-values,
		//	compute the direction of the arc's tangent vector at each one,
		//	and then select a subset such that between any two consecutive u-values,
		//	the arc's direction changes by at most 2° (the maximum acceptable
		//	bending angle).
		
		let theCosMaxAcceptableBendingAngle = 0.99939082701909573001	//	= cos( (π/180) * 2° )
	
		//	Pre-compute theUnitTangents for all candidate u-values.
		//	Normalizing the tangent vectors to unit length -- relative
		//	to the drawing-coordinates metric -- makes it easy
		//	to evaluate how the arc is bending.
		//
		let theUnitTangents = (0 ... Curve.maxArcSegmentCount).map{
			unitLengthVector(
				v: tangentVector(
						u: Double($0) / Double(Curve.maxArcSegmentCount),
						ξ: ξ
					),
				metricOfDet1: metricOfDet1
			)
		}
	
		//	Consider each u-value in turn and generate triangle-strip vertics
		//	for a subset such that between any two consecutive u-values,
		//	the arc's direction changes by at most about 2° (the maximum
		//	acceptable bending angle) relative to the drawing-coordinates metric.
		
		var theVertexCount = 0
		var thePreviousAcceptedUnitTangent = SIMD2<Double>.zero
		
		for i in 0 ... Curve.maxArcSegmentCount {
		
			//	Compare unit tangent vectors to decide whether
			//	to generate triangle-strip vertics for this u-value.
			let theAcceptFlag: Bool
			if i == 0 {
			
				//	This is the first u-value, so accept it for sure.
				theAcceptFlag = true
			
				//	Remember the unit tangent vector here
				//	so we can compare it with later values.
				thePreviousAcceptedUnitTangent = theUnitTangents[0]
				
			} else if i == Curve.maxArcSegmentCount {
			
				//	This is the last u-value, so accept it for sure.
				theAcceptFlag = true
			
				//	Just to be tidy, clear thePreviousAcceptedUnitTangent.
				thePreviousAcceptedUnitTangent = SIMD2<Double>.zero
				
			} else {	//	1 ≤ i ≤ Curve.maxArcSegmentCount - 1

				//	Accept this u-value iff its tangent vector differs
				//	by at least 2° from the most recently accepted tangent vector.
				//
				//		Note:  Strictly speaking, to keep the angle difference
				//		under 2° we'd need to accept the last u-value for which
				//		the difference is less, rather than the first u-value
				//		for which it's more.  But in practice the angle varies
				//		slowly enough that accepting the first u-value
				//		whose tangent vector differs by more than 2° is
				//		plenty good enough.  That 2° cutoff value is a bit
				//		arbitrary in any case.
				//
				
				//	Compute the inner product of Prev = thePreviousAcceptedUnitTangent
				//	and T = theUnitTangents[i+1] relative to the metric m
				//
				//		( Prev₀ Prev₁ )( m₀₀ m₀₁ )( T₀ )
				//		               ( m₁₀ m₁₁ )( T₁ )
				//
				
				let theInnerProduct
					= thePreviousAcceptedUnitTangent[0] * metricOfDet1[0][0] * theUnitTangents[i][0]
					+ thePreviousAcceptedUnitTangent[0] * metricOfDet1[0][1] * theUnitTangents[i][1]
					+ thePreviousAcceptedUnitTangent[1] * metricOfDet1[1][0] * theUnitTangents[i][0]
					+ thePreviousAcceptedUnitTangent[1] * metricOfDet1[1][1] * theUnitTangents[i][1]

				//	The tangent vectors have unit length, so
				//
				//		<Prev, T> = |Prev| |T| cos θ
				//		          = cos θ
				//
				//	The bending angle is too big iff its cosine is too small.
				//
				if theInnerProduct < theCosMaxAcceptableBendingAngle {
				
					//	The bending angle between thePreviousAcceptedUnitTangent
					//	and theUnitTangents[i] exceeds 2°.  So let's accept
					//	the current u-value, and let the code below add
					//	a pair of vertices to the scratchBuffer.
					theAcceptFlag = true
				
					//	The tangent vector for the current u-value
					//	becomes the new "previous accepted unit tangent".
					thePreviousAcceptedUnitTangent = theUnitTangents[i]
				}
				else
				{
					//	Skip the current u-value and continue on to the next one.
					theAcceptFlag = false
				
					//	Leave thePreviousAcceptedUnitTangent as it is.
				}
			}

			if theAcceptFlag {
			
				//	Note the current u-value.
				let u	= Double(i) / Double(Curve.maxArcSegmentCount)
				let uu	= 1.0 - u

				//	First find the point on the curve's centerline for this value of u,
				//	ignoring the curve's thickness.  Recall that the spline
				//	is parameterized by
				//
				//		S(u) = ξ₀(1-u) + ξ₁u + ξ₂(1-u)³ + ξ₃u³
				//
				//	where the ξ are constants and u runs from 0 to 1.
				//
				let theCenterline: SIMD2<Double>
					=           uu * ξ[0]
					+           u  * ξ[1]
					+ uu * uu * uu * ξ[2]
					+ u  * u  * u  * ξ[3]

				//	To account for the curve's thickness,
				//	we'll need a unit-length normal vector.
				let theUnitNormal = orthogonalVector(
										to: theUnitTangents[i],
										metricOfDet1: metricOfDet1)

				//	Offset alternate vertices to either side of the centerline,
				//	by the Curve's half-thickness times theNormal
				//	(keeping in mind that theNormal has unit length
				//	in the metric of the unit-area parallelogram).

				let theTriStripVertex0 =  theCenterline  -  0.5 * itsThickness * theUnitNormal
				let theTriStripVertex1 =  theCenterline  +  0.5 * itsThickness * theUnitNormal
			
				scratchBuffer[theVertexCount + 0] = SIMD2<Float32>(theTriStripVertex0)
				scratchBuffer[theVertexCount + 1] = SIMD2<Float32>(theTriStripVertex1)

				theVertexCount += 2
			}
		}
		
		//	Render the triangle strip vertices.

		renderEncoder.setVertexBytes(
			scratchBuffer,
			length: theVertexCount * MemoryLayout<SIMD2<Float32>>.stride,
			index: BufferIndexVFVertexAttributes)

		renderEncoder.drawPrimitives(
			type: .triangleStrip,
			vertexStart: 0,
			vertexCount: theVertexCount,
			instanceCount: symmetryCount)
	}
	
	private func renderInitialHalfDot(
		atNode node: SplineNode,
		renderEncoder: MTLRenderCommandEncoder,
		metricOfDet1: simd_double2x2,
		scratchBuffer: UnsafeMutablePointer<SIMD2<Float32>>,	//	guaranteed to be big enough
		symmetryCount: Int
	) {
	
		//	For conciseness.
		let ξ: simd_double4x2 = node.ξ
		
		//	Compute a unit tangent vector at the beginning of the arc,
		//	using the formula
		//
		//		∂S
		//		-- = -ξ₀ + ξ₁ - 3ξ₂(1 - u)² + 3ξ₃u²
		//		∂u
		//
		//		   = -ξ₀ + ξ₁ - 3ξ₂(1 - 0)² + 3ξ₃0²
		//
		//		   = -ξ₀ + ξ₁ - 3ξ₂
		//
		//	Orient the half-dot in the direction opposite the direction of the arc itself.
		//
		let theTangent: SIMD2<Double> = ξ[0] - ξ[1] + 3.0*ξ[2]
		let theUnitTangent = unitLengthVector(
								v: theTangent,
								metricOfDet1: metricOfDet1)
		
		//	Let theUnitNormal be orthogonal to theUnitTangent.
		let theUnitNormal = orthogonalVector(
								to: theUnitTangent,
								metricOfDet1: metricOfDet1)

		renderHalfDot(
			center: node.itsNodeLocation,
			unitTangent: theUnitTangent,
			unitNormal: theUnitNormal,
			renderEncoder: renderEncoder,
			scratchBuffer: scratchBuffer,
			symmetryCount: symmetryCount)
	}
	
	private func renderFinalHalfDot(
		penultimateNode: SplineNode,
		ultimateNode: SplineNode,
		renderEncoder: MTLRenderCommandEncoder,
		metricOfDet1: simd_double2x2,
		scratchBuffer: UnsafeMutablePointer<SIMD2<Float32>>,	//	guaranteed to be big enough
		symmetryCount: Int
	) {
	
		//	For conciseness.
		let ξ: simd_double4x2 = penultimateNode.ξ
		
		//	Compute a unit tangent vector at the end of the arc,
		//	using the formula
		//
		//		∂S
		//		-- = -ξ₀ + ξ₁ - 3ξ₂(1 - u)² + 3ξ₃u²
		//		∂u
		//
		//		   = -ξ₀ + ξ₁ - 3ξ₂(1 - 1)² + 3ξ₃1²
		//
		//		   = -ξ₀ + ξ₁ + 3ξ₃
		//
		//	Orient the half-dot in the same direction as the arc itself.
		//
		let theTangent: SIMD2<Double> = -ξ[0] + ξ[1] + 3.0*ξ[3]
		let theUnitTangent = unitLengthVector(
								v: theTangent,
								metricOfDet1: metricOfDet1)
		
		//	Let theUnitNormal be orthogonal to theUnitTangent.
		let theUnitNormal = orthogonalVector(
								to: theUnitTangent,
								metricOfDet1: metricOfDet1)

		renderHalfDot(
			center: ultimateNode.itsNodeLocation,
			unitTangent: theUnitTangent,
			unitNormal: theUnitNormal,
			renderEncoder: renderEncoder,
			scratchBuffer: scratchBuffer,
			symmetryCount: symmetryCount)
	}
	
	private func renderHalfDot(
			center: SIMD2<Double>,
			unitTangent: SIMD2<Double>,
			unitNormal: SIMD2<Double>,
			renderEncoder: MTLRenderCommandEncoder,
			scratchBuffer: UnsafeMutablePointer<SIMD2<Float32>>,	//	guaranteed to be big enough
			symmetryCount: Int
	) {
	
		for i in 0 ..< gUnitHalfCircleVertexCount {

			let theTriStripVertex
				= center
				+ 0.5 * itsThickness * gUnitCircleVertices[i][0] * unitTangent
				+ 0.5 * itsThickness * gUnitCircleVertices[i][1] * unitNormal
			
			//	Convert to SIMD2<Float32> for the GPU.
			scratchBuffer[i] = SIMD2<Float32>(theTriStripVertex)
		}

		renderEncoder.setVertexBytes(
			scratchBuffer,
			length: gUnitHalfCircleVertexCount * MemoryLayout<SIMD2<Float32>>.stride,
			index: BufferIndexVFVertexAttributes)

		renderEncoder.drawPrimitives(
			type: .triangleStrip,
			vertexStart: 0,
			vertexCount: gUnitHalfCircleVertexCount,
			instanceCount: symmetryCount)
	}
	
	
// MARK: -
// MARK: Control handle

	func renderControlHandles(
		selectedNode: SplineNode?,	//	= nil if no node is selected
		renderEncoder: MTLRenderCommandEncoder,
		symmetryCount: Int
	) {
	
		for theNode in itsSpline.itsNodes {
		
			var thePlacement = ControlHandlePlacement(
				itsCenter: SIMD2<Float32>(theNode.itsNodeLocation),
				itsRadius: Float32(0.5 * itsThickness))
							//	multiplication by 0.5 converts diameter to radius
			
			let theDarkColor = ( theNode.itsNodeType == .smooth ?
									SIMD4<Float16>(0.5, 0.5, 0.5, 1.0) :
									SIMD4<Float16>(0.0, 0.0, 0.0, 1.0) )
			let theLightColor = SIMD4<Float16>(1.0, 1.0, 1.0, 1.0)
			var theColors = ( theNode === selectedNode ?
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
	}

	override func hitControlHandle(
		touchPointInExtendedUnitCellCoordinates: SIMD2<Double>,
		wallpaperGroup: WallpaperGroup,
		metricOfDet1: simd_double2x2,
		fillMarkerRadius: Double	//	used only for Fills
	) -> ControlHandleHit?
	{

		//	Test each SplineNode for a control-handle hit.
		//	If several nodes sit close to each other,
		//	select the node closest to the tap point.
		var thePossibleHitControlHandle: ControlHandleHit?
		var theTapError = Double.infinity

		for theNode in itsSpline.itsNodes {
		
			if let theHitControlHandle = hitImageOfControlHandle(
				touchPointInExtendedUnitCellCoordinates: touchPointInExtendedUnitCellCoordinates,
				controlHandleCenter: theNode.itsNodeLocation,
				controlHandleMeanRadius: 0.5 * itsThickness,
				splineNode: theNode,
				wallpaperGroup: wallpaperGroup,
				metricOfDet1: metricOfDet1) {
			
				if theHitControlHandle.itsTapError < theTapError {
				
					thePossibleHitControlHandle = theHitControlHandle
					theTapError = theHitControlHandle.itsTapError
				}
			}
		}
		
		return thePossibleHitControlHandle
	}
	
	
// MARK: -
// MARK: Vector computations

	private func tangentVector(
		u: Double,			//	∈ [0.0, 1.0]
		ξ: simd_double4x2	//	spline parameters
	) -> SIMD2<Double> {
	
		let uu	= 1.0 - u

		//	Compute a raw tangent vector T
		//	using the derivative of the formula S(u)
		//	given at the top of renderArc().
		//
		//		∂S
		//		-- = -ξ₀ + ξ₁ - 3ξ₂(1-u)² + 3ξ₃u²
		//		∂u
		//
		let theTangent: SIMD2<Double>
			=                -ξ[0]
			+                 ξ[1]
			- 3.0 * uu * uu * ξ[2]	//	Keep the scalar factors together, otherwise
			+ 3.0 * u  * u  * ξ[3]	//		the Swift compiler "can't type-check
									//		the expression in a reasonable time".
									
		return theTangent
	}
}
