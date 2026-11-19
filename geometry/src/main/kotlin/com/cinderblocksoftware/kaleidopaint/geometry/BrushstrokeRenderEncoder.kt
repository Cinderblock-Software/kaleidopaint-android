// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

//	Where Dot and Curve send what they draw
//
//	In the Swift original, Dot.render() and Curve.render() compute
//	a triangle strip and hand it straight to Metal:
//
//		renderEncoder.setVertexBytes(scratchBuffer, length: …, index: BufferIndexVFVertexAttributes)
//		renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: …,
// instanceCount: …)
//
//	and for a control handle
//
//		renderEncoder.setVertexBytes(&thePlacement, …, index: BufferIndexVFMisc)
//		renderEncoder.setFragmentBytes(&theColors, …, index: BufferIndexFFMisc)
//		renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: …,
// instanceCount: …)
//
//	This module has no graphics library to call, so each of those
//	groups of calls becomes one call on the interface below.
//	The app's OpenGL ES renderer implements it;
//	the unit tests implement it to read the vertices back.

interface BrushstrokeRenderEncoder {

    //	Draw the first vertexCount vertices of the scratch buffer
    //	as a triangle strip, once for each of instanceCount symmetries.
    fun drawTriangleStrip(
        vertices: VertexScratchBuffer,
        vertexCount: Int,
        instanceCount: Int,
    )

    //	Draw one control handle (a square of vertexCount vertices
    //	which the shaders turn into a ringed disk),
    //	once for each of instanceCount symmetries.
    fun drawControlHandle(
        placement: ControlHandlePlacement,
        colors: ControlHandleColors,
        vertexCount: Int,
        instanceCount: Int,
    )
}

//	Stands in for Swift's UnsafeMutablePointer<SIMD2<Float32>>:
//	a reusable buffer of single-precision 2D vertices,
//	stored as x₀ y₀ x₁ y₁ … ready to hand to the GPU.
class VertexScratchBuffer(vertexCapacity: Int) {

    val itsFloats = FloatArray(2 * vertexCapacity)

    val vertexCapacity: Int
        get() = itsFloats.size / 2

    operator fun set(index: Int, vertex: Float2) {
        itsFloats[2 * index + 0] = vertex.x
        itsFloats[2 * index + 1] = vertex.y
    }

    operator fun get(index: Int): Float2 =
        Float2(itsFloats[2 * index + 0], itsFloats[2 * index + 1])
}
