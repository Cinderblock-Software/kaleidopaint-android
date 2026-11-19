// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
//
//	Reference values for the Kotlin port of KaleidoPaint's maths.
//
//	This program is compiled together with upstream's own, unmodified
//	Swift files (see build.sh) and prints what they compute for a fixed
//	set of inputs, one value per line:
//
//		key <tab> type <tab> values separated by spaces
//
//	where type is S (a string), I (integers), D (doubles) or F (floats).
//	geometry/src/test/kotlin/…/ReferenceScenario.kt runs the same inputs
//	through the Kotlin port, and ReferenceTest.kt compares the two.
//
//	Keep the two scenario files in step:  a line added here
//	needs its twin there, with the same key.

import Foundation
import simd


// MARK: -
// MARK: Output

func emit(_ key: String, string: String) {
	print("\(key)\tS\t\(string)")
}
func emit(_ key: String, ints: [Int]) {
	print("\(key)\tI\t" + ints.map { "\($0)" }.joined(separator: " "))
}
func emit(_ key: String, int: Int) {
	emit(key, ints: [int])
}
func emit(_ key: String, bool: Bool) {
	emit(key, ints: [bool ? 1 : 0])
}
func emit(_ key: String, doubles: [Double]) {
	print("\(key)\tD\t" + doubles.map { "\($0)" }.joined(separator: " "))
}
func emit(_ key: String, double: Double) {
	emit(key, doubles: [double])
}
func emit(_ key: String, floats: [Float32]) {
	print("\(key)\tF\t" + floats.map { "\($0)" }.joined(separator: " "))
}
func emit(_ key: String, vector: SIMD2<Double>) {
	emit(key, doubles: [vector[0], vector[1]])
}
func emit(_ key: String, matrix: simd_double2x2) {
	emit(key, doubles: [matrix[0][0], matrix[0][1], matrix[1][0], matrix[1][1]])
}
func emit(_ key: String, matrix: simd_double3x3) {
	var theEntries: [Double] = []
	for theColumn in 0 ..< 3 {
		for theRow in 0 ..< 3 {
			theEntries.append(matrix[theColumn][theRow])
		}
	}
	emit(key, doubles: theEntries)
}
func flatten(_ segments: [(SIMD2<Double>, SIMD2<Double>)]) -> [Double] {
	return segments.flatMap { [$0.0[0], $0.0[1], $0.1[0], $0.1[1]] }
}
func flatten(_ points: [SIMD2<Double>]) -> [Double] {
	return points.flatMap { [$0[0], $0[1]] }
}


// MARK: -
// MARK: Shared inputs

//	A rotation by θ, a dilation by scale and then a translation,
//	in the form UnitCellPlacement.transform() expects.
//	The cosine and sine are passed in as literals so that
//	both languages start from exactly the same numbers.
func similarity(
	cosθ: Double,
	sinθ: Double,
	scale: Double,
	translation: SIMD2<Double>
) -> simd_double3x2 {
	return simd_double3x2([
		SIMD2<Double>( scale * cosθ, scale * sinθ),
		SIMD2<Double>(-scale * sinθ, scale * cosθ),
		translation
	])
}

//	cos and sin of 0.03 radians (close enough to horizontal to snap)
//	and of 0.2 radians (not close enough).
let gCos003 = 0.99955003374898754
let gSin003 = 0.029995500202495660
let gCos02  = 0.98006657784124163
let gSin02  = 0.19866933079506122

//	Placements to measure with:  the default for a square cell,
//	the default for a hexagonal cell, and a sheared, rotated, shifted cell.
func namedPlacements() -> [(String, UnitCellPlacement)] {

	let theSquare = UnitCellPlacement(defaultForWallpaperGroup: .wpgO)
	let theRhombus = UnitCellPlacement(defaultForWallpaperGroup: .wpg333)

	var theSheared = UnitCellPlacement(defaultForWallpaperGroup: .wpg2222)
	theSheared.itsTranslations = simd_double2x2(
		SIMD2<Double>(0.31, 0.04),
		SIMD2<Double>(0.17, 0.22)
	)
	theSheared.itsCorner = SIMD2<Double>(-0.07, 0.11)

	return [("square", theSquare), ("rhombus", theRhombus), ("sheared", theSheared)]
}

//	Curves to measure with.  "c" marks a corner node;  the rest are smooth.
func namedSplines() -> [(String, CubicSpline)] {

	func spline(_ nodes: [(Double, Double, String)]) -> CubicSpline {
		let theSpline = CubicSpline()
		for (x, y, type) in nodes {
			theSpline.append(SplineNode(
				location: SIMD2<Double>(x, y),
				type: type == "c" ? .corner : .smooth))
		}
		return theSpline
	}

	//	A long curve whose nodes come from exact arithmetic
	//	(a remainder is exact in both languages; a cosine might not be).
	var theLongNodes: [(Double, Double, String)] = []
	for i in 0 ..< 40 {
		let x = (Double(i) * 0.6180339887).truncatingRemainder(dividingBy: 1.0)
		let y = (Double(i) * 0.7548776662).truncatingRemainder(dividingBy: 1.0)
		theLongNodes.append((0.2 + 0.6 * x, 0.2 + 0.6 * y, i % 7 == 3 ? "c" : "s"))
	}

	return [
		("single", spline([
			(0.4, 0.6, "s")])),
		("two", spline([
			(0.1, 0.2, "s"), (0.8, 0.6, "s")])),
		("three", spline([
			(0.1, 0.2, "s"), (0.45, 0.7, "s"), (0.8, 0.3, "s")])),
		("wave", spline([
			(0.10, 0.50, "s"), (0.20, 0.72, "s"), (0.35, 0.31, "s"), (0.50, 0.66, "s"),
			(0.62, 0.28, "s"), (0.80, 0.55, "s"), (0.93, 0.47, "s")])),
		("corners", spline([
			(0.15, 0.15, "c"), (0.30, 0.60, "s"), (0.50, 0.80, "c"),
			(0.55, 0.35, "c"), (0.75, 0.20, "s"), (0.90, 0.65, "s")])),
		("coincident", spline([
			(0.2, 0.2, "s"), (0.5, 0.5, "s"), (0.5, 0.5, "s"), (0.8, 0.3, "s")])),
		("far", spline([
			(1.62, -2.31, "s"), (1.75, -2.12, "s"), (1.93, -2.44, "c"), (2.21, -2.20, "s")])),
		("halves", spline([
			(1.75, 2.5, "s"), (2.25, 3.5, "s")])),
		("long", spline(theLongNodes))
	]
}

func indexOfNode(_ node: SplineNode?, in spline: CubicSpline) -> Int {
	guard let theNode = node else {
		return -1
	}
	return spline.itsNodes.firstIndex(where: { $0 === theNode }) ?? -1
}


// MARK: -
// MARK: Wallpaper groups

func emitWallpaperGroups() {

	emit("groups.count", int: WallpaperGroup.allCases.count)

	for (i, theGroup) in WallpaperGroup.allCases.enumerated() {

		let k = "groups.\(i)"
		let theTorusGroup = theGroup.torusGroup

		emit("\(k).rawValue", string: theGroup.rawValue)
		emit("\(k).id", string: theGroup.id)
		emit("\(k).orbifoldName", string: theGroup.orbifoldName)
		emit("\(k).IUCName", string: theGroup.IUCName)

		emit("\(k).elementCount", int: theTorusGroup.itsElements.count)
		for (j, theElement) in theTorusGroup.itsElements.enumerated() {
			emit("\(k).element.\(j).matrix", matrix: theElement.itsMatrix)
			emit("\(k).element.\(j).color", doubles: [
				theElement.itsColor.r, theElement.itsColor.g, theElement.itsColor.b, theElement.itsColor.a])
		}

		emit("\(k).constraints.rhombus", bool: theTorusGroup.itsUnitCellShapeConstraints.contains(.rhombus))
		emit("\(k).constraints.angle_2π_over_4", bool: theTorusGroup.itsUnitCellShapeConstraints.contains(.angle_2π_over_4))
		emit("\(k).constraints.angle_2π_over_6", bool: theTorusGroup.itsUnitCellShapeConstraints.contains(.angle_2π_over_6))
		emit("\(k).rigidity", string: "\(theTorusGroup.itsRigidity)")

		emit("\(k).mirrorSegments", doubles: flatten(theTorusGroup.itsMirrorSegments))
		emit("\(k).gyrationPoints", doubles: flatten(theTorusGroup.itsGyrationPoints))
		emit("\(k).glideReflectionSegments", doubles: flatten(theTorusGroup.itsGlideReflectionSegments))
	}
}


// MARK: -
// MARK: Constants

func emitConstants() {

	emit("constants.gSafeRegionInset", double: gSafeRegionInset)
	emit("constants.shifts", ints: [gMinShift, gMaxShift, gNumShifts])

	emit("constants.gUnitCircleVertices", doubles: flatten(gUnitCircleVertices))
	emit("constants.gUnitCircleVertexCount", int: gUnitCircleVertexCount)
	emit("constants.gUnitHalfCircleVertexCount", int: gUnitHalfCircleVertexCount)
	emit("constants.gRawControlHandleVertices", doubles: flatten(gRawControlHandleVertices))
	emit("constants.gControlHandleVertexCount", int: gControlHandleVertexCount)

	emit("constants.Curve", ints: [
		Curve.maxArcSegmentCount,
		Curve.maxArcVertexCount,
		Curve.maxPointVertexCount,
		Curve.triStripBufferVertexCount])
	emit("constants.Dot.triStripBufferVertexCount", int: Dot.triStripBufferVertexCount)

	emit("constants.SplineNodeType", string:
		SplineNodeType.allCases.map { "\($0.rawValue)/\($0.id)" }.joined(separator: ","))

	for (i, theValue) in [-0.5, -0.001, 0.0, 0.001, 0.0031308, 0.02, 0.04045, 0.18, 0.5, 1.0, 1.25].enumerated() {
		emit("constants.gamma.\(i)", doubles: [
			gammaEncode(theValue), gammaDecode(theValue), clampToZeroOne(theValue)])
	}

	let theColor = LinearDisplayP3Color(r: 0.25, g: 0.5, b: 0.75, a: 1.0)
	emit("constants.color.almostSame", ints: [
		theColor.isAlmostTheSameAs(LinearDisplayP3Color(r: 0.2501, g: 0.5, b: 0.7499, a: 1.0)) ? 1 : 0,
		theColor.isAlmostTheSameAs(LinearDisplayP3Color(r: 0.2601, g: 0.5, b: 0.75, a: 1.0)) ? 1 : 0,
		theColor.isAlmostTheSameAs(LinearDisplayP3Color(r: 0.25, g: 0.5, b: 0.75, a: 0.98)) ? 1 : 0])
	let theHalf = theColor.asSIMDHalf()
	emit("constants.color.asSIMDHalf", floats: [
		Float32(theHalf[0]), Float32(theHalf[1]), Float32(theHalf[2]), Float32(theHalf[3])])
}


// MARK: -
// MARK: Unit cell placement

func emitPlacement(_ key: String, _ placement: UnitCellPlacement) {
	emit("\(key).corner", vector: placement.itsCorner)
	emit("\(key).translations", matrix: placement.itsTranslations)
	emit("\(key).metric", matrix: placement.itsMetricOfDet1)
	emit("\(key).degenerate", bool: placement.unitCellIsDegenerate())
}

func emitUnitCellPlacements() {

	for (i, theGroup) in WallpaperGroup.allCases.enumerated() {

		let k = "placement.\(i)"

		let theDefault = UnitCellPlacement(defaultForWallpaperGroup: theGroup)
		emitPlacement("\(k).default", theDefault)

		//	Rotate by 0.2 radians, dilate and translate…
		var theTransformed = theDefault
		theTransformed.transform(using: similarity(
			cosθ: gCos02, sinθ: gSin02, scale: 1.7, translation: SIMD2<Double>(0.4, -0.9)))
		emitPlacement("\(k).transformed", theTransformed)

		//	…bring the cell back to the origin…
		theTransformed.centerTheUnitCell()
		emitPlacement("\(k).centered", theTransformed)

		//	…and check that a tilt that large doesn't snap.
		theTransformed.snapToViewAlignment()
		emitPlacement("\(k).notSnapped", theTransformed)

		//	A tilt of 0.03 radians does snap.
		var theTilted = theDefault
		theTilted.transform(using: similarity(
			cosθ: gCos003, sinθ: gSin003, scale: 1.0, translation: SIMD2<Double>(0.0, 0.0)))
		emitPlacement("\(k).tilted", theTilted)
		theTilted.snapToViewAlignment()
		emitPlacement("\(k).snapped", theTilted)

		//	The same tilt the other way.
		var theTiltedBack = theDefault
		theTiltedBack.transform(using: similarity(
			cosθ: gCos003, sinθ: -gSin003, scale: 1.0, translation: SIMD2<Double>(0.0, 0.0)))
		theTiltedBack.snapToViewAlignment()
		emitPlacement("\(k).snappedBack", theTiltedBack)
	}

	//	Cells that are too small, too big, too lopsided or too flat.
	let theDegenerateCells: [(String, simd_double2x2)] = [
		("tiny",     simd_double2x2(SIMD2<Double>(0.01, 0.0),  SIMD2<Double>(0.0, 0.01))),
		("huge",     simd_double2x2(SIMD2<Double>(65.0, 0.0),  SIMD2<Double>(0.0, 65.0))),
		("lopsided", simd_double2x2(SIMD2<Double>(9.0, 0.0),   SIMD2<Double>(0.0, 1.0))),
		("flat",     simd_double2x2(SIMD2<Double>(1.0, 0.0),   SIMD2<Double>(1.0, 0.05))),
		("mirrored", simd_double2x2(SIMD2<Double>(0.0, 1.0),   SIMD2<Double>(1.0, 0.0))),
		("fine",     simd_double2x2(SIMD2<Double>(1.0, 0.0),   SIMD2<Double>(0.9, 0.5)))
	]
	for (theName, theTranslations) in theDegenerateCells {
		var thePlacement = UnitCellPlacement(defaultForWallpaperGroup: .wpgO)
		thePlacement.itsTranslations = theTranslations
		emitPlacement("placement.cell.\(theName)", thePlacement)
	}

	emit("placement.shape.equal", ints: [
		UnitCellShape(aspectRatio: 1.5, shear: 0.25) == UnitCellShape(aspectRatio: 1.5, shear: 0.25) ? 1 : 0,
		UnitCellShape(aspectRatio: 1.5, shear: 0.25) == UnitCellShape(aspectRatio: 1.5, shear: 0.5) ? 1 : 0])
}


// MARK: -
// MARK: Coordinate systems

func emitCoordinateSystems() {

	let theViewSizes: [(Double, Double)] = [(390.0, 844.0), (1024.0, 768.0), (1080.0, 2400.0)]
	let theFractions: [(Double, Double)] = [(0.0, 0.0), (0.5, 0.5), (0.03125, 0.9375), (1.0, 1.0), (0.71, 0.13)]

	for (i, (theWidth, theHeight)) in ([(0.0, 0.0)] + theViewSizes).enumerated() {
		let (w, h) = convertPageSizeToDrawingCoordinates(theWidth, theHeight)
		emit("coordinates.pageSize.\(i)", doubles: [w, h])
	}

	for (thePlacementName, thePlacement) in namedPlacements() {
		for (v, (theWidth, theHeight)) in theViewSizes.enumerated() {
			for (p, (fx, fy)) in theFractions.enumerated() {

				let k = "coordinates.\(thePlacementName).view\(v).point\(p)"

				let theDisplayPoint = DisplayPoint(
					x: fx * theWidth,
					y: fy * theHeight,
					viewWidth: theWidth,
					viewHeight: theHeight)

				let theDrawingPoint = convertDisplayCoordinatesToDrawingCoordinates(theDisplayPoint)
				emit("\(k).displayToDrawing", vector: theDrawingPoint)

				let theRoundTrip = convertDrawingCoordinatesToDisplayCoordinates(
					theDrawingPoint, viewWidth: theWidth, viewHeight: theHeight)
				emit("\(k).drawingToDisplay", doubles: [
					theRoundTrip.x, theRoundTrip.y, theRoundTrip.viewWidth, theRoundTrip.viewHeight])

				let theMotion = DisplayPointMotion(
					Δx: (fx - 0.25) * theWidth,
					Δy: (0.4 - fy) * theHeight,
					viewWidth: theWidth,
					viewHeight: theHeight)
				emit("\(k).displayTranslationToDrawing", vector:
					convertDisplayTranslationToDrawingTranslation(theMotion))

				let theExtendedPoint = convertDrawingCoordinatesToExtendedUnitCellCoordinates(
					theDrawingPoint, unitCellPlacement: thePlacement)
				emit("\(k).drawingToExtended", vector: theExtendedPoint)

				emit("\(k).extendedToDrawing", vector:
					convertExtendedUnitCellCoordinatesToDrawingCoordinates(
						theExtendedPoint, unitCellPlacement: thePlacement))

				emit("\(k).extendedToStrict", vector:
					convertExtendedUnitCellCoordinatesToStrictUnitCellCoordinates(theExtendedPoint))

				emit("\(k).displayToExtended", vector:
					convertDisplayCoordinatesToExtendedUnitCellCoordinates(
						theDisplayPoint, unitCellPlacement: thePlacement))

				emit("\(k).displayToStrict", vector:
					convertDisplayCoordinatesToStrictUnitCellCoordinates(
						theDisplayPoint, unitCellPlacement: thePlacement))

				let theBack = convertExtendedUnitCellCoordinatesToDisplayCoordinates(
					SIMD2<Double>(fx * 3.0 - 1.0, fy * 3.0 - 1.0),
					unitCellPlacement: thePlacement,
					viewWidth: theWidth,
					viewHeight: theHeight)
				emit("\(k).extendedToDisplay", doubles: [
					theBack.x, theBack.y, theBack.viewWidth, theBack.viewHeight])
			}
		}
	}
}


// MARK: -
// MARK: Splines

func emitSpline(_ key: String, _ spline: CubicSpline) {

	emit("\(key).nodeCount", int: spline.itsNodes.count)

	for (i, theNode) in spline.itsNodes.enumerated() {

		emit("\(key).node.\(i).location", vector: theNode.itsNodeLocation)
		emit("\(key).node.\(i).type", string: theNode.itsNodeType.rawValue)

		let ξ = theNode.ξ
		emit("\(key).node.\(i).ξ", doubles: [
			ξ[0][0], ξ[0][1], ξ[1][0], ξ[1][1], ξ[2][0], ξ[2][1], ξ[3][0], ξ[3][1]])

		//	S(u) = ξ₀(1-u) + ξ₁u + ξ₂(1-u)³ + ξ₃u³  at fixed values of u.
		var theSamples: [Double] = []
		for u in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0] {
			let uu = 1.0 - u
			let thePoint: SIMD2<Double>
				=           uu * ξ[0]
				+           u  * ξ[1]
				+ uu * uu * uu * ξ[2]
				+ u  * u  * u  * ξ[3]
			theSamples.append(thePoint[0])
			theSamples.append(thePoint[1])
		}
		emit("\(key).node.\(i).samples", doubles: theSamples)
	}
}

func emitSplines() {

	for (theName, theSpline) in namedSplines() {

		let k = "spline.\(theName)"

		emitSpline("\(k).beforeRefresh", theSpline)

		theSpline.refreshParameterization()
		emitSpline("\(k).refreshed", theSpline)

		//	Split the first, the last and a middle node.
		let theCount = theSpline.itsNodes.count
		for (theLabel, theIndex) in [("first", 0), ("middle", theCount / 2), ("last", theCount - 1)] {
			let (theNodeA, theNodeB) = theSpline.splitNode(theSpline.itsNodes[theIndex])
			emit("\(k).split.\(theLabel).A", vector: theNodeA.itsNodeLocation)
			emit("\(k).split.\(theLabel).A.type", string: theNodeA.itsNodeType.rawValue)
			emit("\(k).split.\(theLabel).B", vector: theNodeB.itsNodeLocation)
			emit("\(k).split.\(theLabel).B.type", string: theNodeB.itsNodeType.rawValue)
		}

		emit("\(k).shift", vector: theSpline.computeShiftToKeepCenteredInUnitCell())
		theSpline.keepCenteredInUnitCell()
		theSpline.refreshParameterization()
		emitSpline("\(k).centered", theSpline)

		theSpline.applyShift(SIMD2<Double>(-2.0, 3.0))
		emit("\(k).shiftedBy(-2,3)", doubles: flatten(theSpline.itsNodes.map { $0.itsNodeLocation }))
	}

	//	An empty curve asks for no shift at all.
	emit("spline.empty.shift", vector: CubicSpline().computeShiftToKeepCenteredInUnitCell())
}


// MARK: -
// MARK: Vector computations

func emitVectorComputations() {

	let theVectors: [SIMD2<Double>] = [
		SIMD2<Double>(1.0, 0.0), SIMD2<Double>(0.0, 1.0), SIMD2<Double>(0.3, -0.4),
		SIMD2<Double>(-2.5, 1.75), SIMD2<Double>(1e-9, 2e-9), SIMD2<Double>(0.0, 0.0)]

	for (thePlacementName, thePlacement) in namedPlacements() {
		for (i, theVector) in theVectors.enumerated() {

			let k = "vectors.\(thePlacementName).\(i)"
			let theMetric = thePlacement.itsMetricOfDet1

			let theUnitVector = unitLengthVector(v: theVector, metricOfDet1: theMetric)
			emit("\(k).unitLengthVector", vector: theUnitVector)
			emit("\(k).orthogonalVector", vector: orthogonalVector(to: theVector, metricOfDet1: theMetric))
			emit("\(k).orthogonalToUnit", vector: orthogonalVector(to: theUnitVector, metricOfDet1: theMetric))
		}
	}
}


// MARK: -
// MARK: Rendering

func emitDraws(_ key: String, _ encoder: RecordingRenderEncoder) {

	emit("\(key).drawCount", int: encoder.itsDraws.count)

	for (i, theDraw) in encoder.itsDraws.enumerated() {
		emit("\(key).draw.\(i).counts", ints: [theDraw.vertexStart, theDraw.vertexCount, theDraw.instanceCount])
		emit("\(key).draw.\(i).vertices", floats: theDraw.vertices)
	}
}

func emitControlHandles(_ key: String, _ encoder: RecordingRenderEncoder) {

	emit("\(key).drawCount", int: encoder.itsDraws.count)

	for (i, theDraw) in encoder.itsDraws.enumerated() {
		emit("\(key).draw.\(i).counts", ints: [theDraw.vertexStart, theDraw.vertexCount, theDraw.instanceCount])
		emit("\(key).draw.\(i).placement", floats: theDraw.controlHandlePlacement)
		emit("\(key).draw.\(i).colors", floats: theDraw.controlHandleColors)
	}
}

func emitRendering() {

	let theEncoder = RecordingRenderEncoder()
	let theScratchBuffer = UnsafeMutablePointer<SIMD2<Float32>>.allocate(
		capacity: max(Curve.triStripBufferVertexCount, Dot.triStripBufferVertexCount))
	defer { theScratchBuffer.deallocate() }

	for (thePlacementName, thePlacement) in namedPlacements() {

		let theMetric = thePlacement.itsMetricOfDet1

		//	Curves
		for (theSplineName, theSpline) in namedSplines() where theSpline.itsNodes.count >= 2 {

			let k = "render.\(thePlacementName).curve.\(theSplineName)"

			theSpline.refreshParameterization()

			let theCurve = Curve(
				color: LinearDisplayP3Color(r: 0.0, g: 0.5, b: 1.0, a: 1.0),
				thickness: 0.03)
			theCurve.itsSpline = theSpline

			theEncoder.reset()
			theCurve.render(
				renderEncoder: theEncoder.asRenderEncoder,
				metricOfDet1: theMetric,
				scratchBuffer: theScratchBuffer,
				symmetryCount: 4)
			emitDraws(k, theEncoder)

			theEncoder.reset()
			theCurve.renderControlHandles(
				selectedNode: theSpline.itsNodes[1],
				renderEncoder: theEncoder.asRenderEncoder,
				symmetryCount: 6)
			emitControlHandles("\(k).handles", theEncoder)

			theEncoder.reset()
			theCurve.renderControlHandles(
				selectedNode: nil,
				renderEncoder: theEncoder.asRenderEncoder,
				symmetryCount: 6)
			emitControlHandles("\(k).handlesUnselected", theEncoder)
		}

		//	Dots
		let theDots: [(SIMD2<Double>, Double)] = [
			(SIMD2<Double>(0.5, 0.5), 0.01),
			(SIMD2<Double>(0.125, 0.875), 0.08),
			(SIMD2<Double>(-0.3, 1.2), 0.0025)]
		for (i, (theCenter, theThickness)) in theDots.enumerated() {

			let k = "render.\(thePlacementName).dot.\(i)"

			let theDot = Dot(
				color: LinearDisplayP3Color(r: 1.0, g: 0.5, b: 0.0, a: 1.0),
				center: theCenter,
				thickness: theThickness)

			theEncoder.reset()
			theDot.render(
				renderEncoder: theEncoder.asRenderEncoder,
				metricOfDet1: theMetric,
				scratchBuffer: theScratchBuffer,
				symmetryCount: 12)
			emitDraws(k, theEncoder)

			theEncoder.reset()
			theDot.renderControlHandle(
				isSelected: true,
				renderEncoder: theEncoder.asRenderEncoder,
				symmetryCount: 12)
			theDot.renderControlHandle(
				isSelected: false,
				renderEncoder: theEncoder.asRenderEncoder,
				symmetryCount: 12)
			emitControlHandles("\(k).handles", theEncoder)
		}
	}

	//	Default constructors
	let theDefaultDot = Dot()
	emit("render.defaults.dot", doubles: [
		theDefaultDot.itsCenter[0], theDefaultDot.itsCenter[1], theDefaultDot.itsThickness,
		theDefaultDot.itsColor.r, theDefaultDot.itsColor.g, theDefaultDot.itsColor.b, theDefaultDot.itsColor.a])
	let theDefaultCurve = Curve()
	emit("render.defaults.curve", doubles: [
		Double(theDefaultCurve.itsSpline.itsNodes.count), theDefaultCurve.itsThickness,
		theDefaultCurve.itsColor.r, theDefaultCurve.itsColor.g, theDefaultCurve.itsColor.b, theDefaultCurve.itsColor.a])
}


// MARK: -
// MARK: Hit testing

func emitHit(_ key: String, _ hit: ControlHandleHit?, _ spline: CubicSpline?) {

	guard let theHit = hit else {
		emit("\(key).hit", bool: false)
		return
	}

	emit("\(key).hit", bool: true)
	emit("\(key).node", int: spline != nil ? indexOfNode(theHit.itsNode, in: spline!) : (theHit.itsNode == nil ? -1 : -2))
	emit("\(key).homeCenter", vector: theHit.itsHomeCenter)
	emit("\(key).hitCenter", vector: theHit.itsHitCenter)
	emit("\(key).symmetry", matrix: theHit.itsSymmetry)
	emit("\(key).tapError", double: theHit.itsTapError)
}

func emitHitTesting() {

	let theFixedTouchPoints: [SIMD2<Double>] = [
		SIMD2<Double>(0.3, 0.2), SIMD2<Double>(0.31, 0.21), SIMD2<Double>(1.3, -0.8),
		SIMD2<Double>(0.7, 0.8), SIMD2<Double>(0.52, 0.48), SIMD2<Double>(-0.69, 1.21),
		SIMD2<Double>(2.05, 3.1), SIMD2<Double>(0.123, 0.456), SIMD2<Double>(0.2, 0.7),
		SIMD2<Double>(0.36, 0.33), SIMD2<Double>(-3.38, 5.69)]

	let theWave = namedSplines().first(where: { $0.0 == "wave" })!.1
	theWave.refreshParameterization()

	for (i, theGroup) in WallpaperGroup.allCases.enumerated() {

		let theMetric = UnitCellPlacement(defaultForWallpaperGroup: theGroup).itsMetricOfDet1

		let theDot = Dot(center: SIMD2<Double>(0.3, 0.2), thickness: 0.02)
		let theCurve = Curve(thickness: 0.02)
		theCurve.itsSpline = theWave

		//	The fixed touch points, plus one just beside
		//	each image of the dot under the torus group.
		var theTouchPoints = theFixedTouchPoints
		for theElement in theGroup.torusGroup.itsElements {
			let theImage = theElement.itsMatrix * SIMD3<Double>(0.3, 0.2, 1.0)
			theTouchPoints.append(SIMD2<Double>(theImage[0] + 0.004, theImage[1] - 0.003))
			theTouchPoints.append(SIMD2<Double>(theImage[0] + 2.0 - 0.002, theImage[1] - 1.0 + 0.005))
		}

		for (j, theTouchPoint) in theTouchPoints.enumerated() {

			emitHit(
				"hit.\(i).dot.\(j)",
				theDot.hitControlHandle(
					touchPointInExtendedUnitCellCoordinates: theTouchPoint,
					wallpaperGroup: theGroup,
					metricOfDet1: theMetric,
					fillMarkerRadius: 0.0),
				nil)

			emitHit(
				"hit.\(i).curve.\(j)",
				theCurve.hitControlHandle(
					touchPointInExtendedUnitCellCoordinates: theTouchPoint,
					wallpaperGroup: theGroup,
					metricOfDet1: theMetric,
					fillMarkerRadius: 0.0),
				theWave)
		}

		//	Touches exactly half way between two images of a fat dot,
		//	where the choice of image depends on how a half gets rounded.
		let theFatDot = Dot(center: SIMD2<Double>(0.25, 0.25), thickness: 0.25)
		let theHalfwayPoints: [SIMD2<Double>] = [
			SIMD2<Double>(0.75, 2.75), SIMD2<Double>(-1.25, -0.25), SIMD2<Double>(-2.25, 3.75), SIMD2<Double>(0.75, 0.25)]
		for (j, theTouchPoint) in theHalfwayPoints.enumerated() {
			emitHit(
				"hit.\(i).halfway.\(j)",
				theFatDot.hitControlHandle(
					touchPointInExtendedUnitCellCoordinates: theTouchPoint,
					wallpaperGroup: theGroup,
					metricOfDet1: theMetric,
					fillMarkerRadius: 0.0),
				nil)
		}
	}
}


// MARK: -
// MARK: Main

//	usage:  reference <directory to write drawings into> <directory of legacy drawings>
//	   or:  reference --external <directory of drawings from elsewhere>
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--external" {
	emitExternalDrawings(URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
	exit(0)
}
precondition(CommandLine.arguments.count == 3, "usage: reference <drawings directory> <legacy directory>")
gDrawingsDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
gLegacyDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

emitWallpaperGroups()
emitConstants()
emitUnitCellPlacements()
emitCoordinateSystems()
emitSplines()
emitVectorComputations()
emitRendering()
emitHitTesting()
emitDrawings()
emitMalformedDrawings()
emitNumberParsing()
emitEditingSession()

emitTileExports()
