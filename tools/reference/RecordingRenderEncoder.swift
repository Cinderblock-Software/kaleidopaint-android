// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
//
//	Upstream's Dot.render() and Curve.render() compute their triangle strips
//	and hand them straight to a Metal MTLRenderCommandEncoder.
//	To read those vertices back without a GPU, give them an object
//	that answers the handful of Objective-C messages they actually send
//	and writes down what it was given.
//
//	MTLRenderCommandEncoder is an Objective-C protocol, so calls on it
//	are dispatched by selector.  An NSObject that implements just
//	those selectors can therefore stand in for the encoder.

import Metal

struct RecordedDraw {
	var vertexStart: Int
	var vertexCount: Int
	var instanceCount: Int
	var vertices: [Float32]				//	the bytes most recently set at BufferIndexVFVertexAttributes
	var controlHandlePlacement: [Float32]	//	the bytes most recently set at BufferIndexVFMisc
	var controlHandleColors: [Float32]	//	the bytes most recently set at BufferIndexFFMisc
}

final class RecordingRenderEncoder: NSObject {

	private var itsVertexBytes: [Int: [UInt8]] = [:]
	private var itsFragmentBytes: [Int: [UInt8]] = [:]
	private(set) var itsDraws: [RecordedDraw] = []

	var asRenderEncoder: MTLRenderCommandEncoder {
		return unsafeBitCast(self, to: MTLRenderCommandEncoder.self)
	}

	func reset() {
		itsVertexBytes = [:]
		itsFragmentBytes = [:]
		itsDraws = []
	}

	@objc(setVertexBytes:length:atIndex:)
	func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
		itsVertexBytes[index] = [UInt8](UnsafeRawBufferPointer(start: bytes, count: length))
	}

	@objc(setFragmentBytes:length:atIndex:)
	func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
		itsFragmentBytes[index] = [UInt8](UnsafeRawBufferPointer(start: bytes, count: length))
	}

	@objc(drawPrimitives:vertexStart:vertexCount:instanceCount:)
	func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) {

		precondition(type == .triangleStrip, "the brushstrokes draw only triangle strips")

		//	Triangle strip vertices are SIMD2<Float32>.
		let theVertices: [Float32] = (itsVertexBytes[Int(BufferIndexVFVertexAttributes)] ?? [])
			.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) }

		//	ControlHandlePlacement is a simd_float2 and a float.
		var thePlacement: [Float32] = []
		if let theBytes = itsVertexBytes[Int(BufferIndexVFMisc)] {
			theBytes.withUnsafeBytes {
				let p = $0.load(as: ControlHandlePlacement.self)
				thePlacement = [p.itsCenter[0], p.itsCenter[1], p.itsRadius]
			}
		}

		//	ControlHandleColors is two simd_half4.
		var theColors: [Float32] = []
		if let theBytes = itsFragmentBytes[Int(BufferIndexFFMisc)] {
			theBytes.withUnsafeBytes {
				let c = $0.load(as: ControlHandleColors.self)
				for i in 0 ..< 4 { theColors.append(Float32(c.itsInnerColor[i])) }
				for i in 0 ..< 4 { theColors.append(Float32(c.itsOuterColor[i])) }
			}
		}

		itsDraws.append(RecordedDraw(
			vertexStart: vertexStart,
			vertexCount: vertexCount,
			instanceCount: instanceCount,
			vertices: Array(theVertices.prefix(2 * vertexCount)),
			controlHandlePlacement: thePlacement,
			controlHandleColors: theColors))
	}
}
