//	KaleidoPaintDot.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import Metal


class Dot: Brushstroke {
	
	//	The Dot's center in [0,1] unit cell coordinates.
	//	Specifies a single point, which will get transformed
	//	under the action of the torus group.
	var itsCenter: SIMD2<Double>

	static let triStripBufferVertexCount = gUnitCircleVertexCount

	init(
		color: LinearDisplayP3Color
			= LinearDisplayP3Color(r: 1.0, g: 0.0, b: 1.0, a: 1.0),
		center: SIMD2<Double> = SIMD2<Double>.zero,
		thickness: Double = 0.01
	) {
	
		itsCenter = center
		
		super.init(color: color, thickness: thickness)
	}
	
	override func render(
		renderEncoder: MTLRenderCommandEncoder,
		metricOfDet1: simd_double2x2,
		scratchBuffer: UnsafeMutablePointer<SIMD2<Float32>>,	//	guaranteed to be big enough
		symmetryCount: Int
	) {
	
		//	Choose a pair of vectors that will
		//	be orthonormal in drawing coordinates.
		let theBasisVectorA = unitLengthVector(
								v: SIMD2<Double>(1.0, 0.0),	//	arbitrary non-zero vector
								metricOfDet1: metricOfDet1)
		let theBasisVectorB = orthogonalVector(
								to: theBasisVectorA,
								metricOfDet1: metricOfDet1)

		for i in 0 ..< gUnitCircleVertexCount {

			let theTriStripVertex
				= itsCenter
				+ 0.5 * itsThickness * gUnitCircleVertices[i][0] * theBasisVectorA
				+ 0.5 * itsThickness * gUnitCircleVertices[i][1] * theBasisVectorB
			
			//	Convert to SIMD2<Float32> for the GPU.
			scratchBuffer[i] = SIMD2<Float32>(theTriStripVertex)
		}

		renderEncoder.setVertexBytes(
			scratchBuffer,
			length: gUnitCircleVertexCount * MemoryLayout<SIMD2<Float32>>.stride,
			index: BufferIndexVFVertexAttributes)

		renderEncoder.drawPrimitives(
			type: .triangleStrip,
			vertexStart: 0,
			vertexCount: gUnitCircleVertexCount,
			instanceCount: symmetryCount)
	}
	
	
// MARK: -
// MARK: Control handle

	func renderControlHandle(
		isSelected: Bool,
		renderEncoder: MTLRenderCommandEncoder,
		symmetryCount: Int
	) {
		//	The diameter of the control point should be less than
		//	the diameter of the dot itself, so that the dot remains visible.
		let theScaleFactor = 0.5
		var thePlacement = ControlHandlePlacement(
			itsCenter: SIMD2<Float32>(itsCenter),
			itsRadius: Float32(theScaleFactor * 0.5 * itsThickness))
						//	multiplication by 0.5 converts diameter to radius
		
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
		fillMarkerRadius: Double	//	used only for Fills
	) -> ControlHandleHit?
	{
		return hitImageOfControlHandle(
			touchPointInExtendedUnitCellCoordinates: touchPointInExtendedUnitCellCoordinates,
			controlHandleCenter: itsCenter,
			controlHandleMeanRadius: 0.5 * itsThickness,
			splineNode: nil,
			wallpaperGroup: wallpaperGroup,
			metricOfDet1: metricOfDet1)
	}
}
